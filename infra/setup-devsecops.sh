#!/bin/bash
# =====================================================================
#  setup-devsecops.sh - Installation complete sur Kali, Debian, Ubuntu ou Fedora
#
#  Installe et configure SANS intervention manuelle :
#    Java 21 (ou 17), Maven, Git, Docker, Jenkins (plugins, admin, credentials,
#    serveur SonarQube, job pipeline), SonarQube (mot de passe, token,
#    webhook), Nexus (mot de passe, settings.xml), Prometheus, Grafana,
#    images des scanners de securite, puis lance le premier build.
#
#  Prerequis : le projet est deja pousse sur GitHub (depot public).
#  Usage     : sudo bash setup-devsecops.sh
#  Duree     : 25 a 45 min selon la connexion (estimation).
# =====================================================================
set -euo pipefail

# ---------------------------------------------------------------------
# 0. Parametres
# ---------------------------------------------------------------------
GITHUB_REPO="${GITHUB_REPO:-https://github.com/aminechaouachi1/achat-devsecops.git}"
GIT_BRANCH="${GIT_BRANCH:-main}"
JOB_NAME="achat-devsecops"
INFRA_DIR="/opt/devsecops"
CRED_FILE="/root/devsecops-identifiants.txt"

log()  { echo -e "\n\033[1;34m==> $*\033[0m"; }
ok()   { echo -e "\033[1;32m    OK : $*\033[0m"; }
warn() { echo -e "\033[1;33m    ATTENTION : $*\033[0m"; }

if [ "$(id -u)" -ne 0 ]; then echo "Lancez avec sudo : sudo bash $0"; exit 1; fi

# Detection de la distribution
. /etc/os-release
case "${ID:-}" in
  kali|debian|ubuntu) FAMILY="debian" ;;
  fedora)             FAMILY="fedora" ;;
  *) case "${ID_LIKE:-}" in
       *debian*|*ubuntu*) FAMILY="debian" ;;
       *fedora*|*rhel*)   FAMILY="fedora" ;;
       *) echo "Distribution non supportee : ${ID:-inconnue}"; exit 1 ;;
     esac ;;
esac
echo "Distribution detectee : ${PRETTY_NAME:-$ID} (famille $FAMILY)"

# Mots de passe generes (respectent les regles de complexite SonarQube / Nexus)
gen() { echo "$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 12)Aa1#"; }
JENKINS_ADMIN_PASSWORD="$(gen)"
SONAR_ADMIN_PASSWORD="$(gen)"
NEXUS_ADMIN_PASSWORD="$(gen)"
MYSQL_ROOT_PASSWORD="$(openssl rand -hex 12)"

echo "Depot GitHub utilise : $GITHUB_REPO (branche $GIT_BRANCH)"
read -r -p "Identifiant Docker Hub (Entree pour ignorer le push) : " DOCKERHUB_USER || true
DOCKERHUB_TOKEN=""
if [ -n "${DOCKERHUB_USER:-}" ]; then
  read -r -s -p "Access token Docker Hub (saisie masquee) : " DOCKERHUB_TOKEN; echo
else
  DOCKERHUB_USER="non-configure"; DOCKERHUB_TOKEN="non-configure"
  warn "Docker Hub non configure : le stage 'P3 - Push image' echouera."
fi

VM_IP="$(ip -4 addr show | awk '/inet / && $2 !~ /^127\./ && $2 !~ /^172\./ {sub(/\/.*/,"",$2); print $2}' | tail -n1)"
VM_IP="${VM_IP:-localhost}"

# ---------------------------------------------------------------------
# 1. Paquets de base, swap, parametre noyau
# ---------------------------------------------------------------------
log "1/9 Paquets de base (Java, Maven, Git, jq...)"
if [ "$FAMILY" = "debian" ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  JDK_PKG="default-jdk"
  for j in openjdk-21-jdk openjdk-17-jdk; do
    if apt-cache show "$j" >/dev/null 2>&1; then JDK_PKG="$j"; break; fi
  done
  apt-get install -y "$JDK_PKG" maven git curl wget jq ca-certificates fontconfig openssl unzip gnupg iproute2
else
  dnf install -y java-21-openjdk-devel maven git curl wget jq ca-certificates fontconfig openssl unzip iproute
fi
ok "$(java -version 2>&1 | head -n1)"
JAVA_MAJOR="$(java -version 2>&1 | head -n1 | sed -E 's/.*version "([0-9]+).*/\1/')"
if [ "${JAVA_MAJOR:-0}" -lt 17 ]; then echo "Java 17 ou plus requis (trouve : $JAVA_MAJOR)"; exit 1; fi

# Swap de 4 Go (pas sur btrfs, systeme par defaut de Fedora qui a deja du zram)
if [ "$(stat -f -c %T /)" != "btrfs" ] && ! swapon --show | grep -q "/swapfile"; then
  log "Ajout de 4 Go de swap (evite les plantages par manque de RAM)"
  fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

# Fedora : SELinux bloquerait l acces des conteneurs scanners au workspace Jenkins
if [ "$FAMILY" = "fedora" ] && command -v getenforce >/dev/null && [ "$(getenforce)" = "Enforcing" ]; then
  warn "SELinux passe en mode permissive (environnement de lab) : a mentionner dans le rapport"
  setenforce 0
  sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
fi

sysctl -w vm.max_map_count=524288
grep -q "vm.max_map_count" /etc/sysctl.conf || echo "vm.max_map_count=524288" >> /etc/sysctl.conf

# ---------------------------------------------------------------------
# 2. Docker
# ---------------------------------------------------------------------
log "2/9 Docker"
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  if [ "$FAMILY" = "fedora" ]; then
    curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif [ "${ID:-}" = "kali" ]; then
    # Kali n est pas supporte par get.docker.com : depot Docker Debian (methode de la doc Kali)
    apt-get remove -y docker.io docker-compose docker-doc podman-docker containerd runc >/dev/null 2>&1 || true
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    curl -fsSL https://get.docker.com | sh
  fi
fi
systemctl enable --now docker
SUDO_USER_NAME="${SUDO_USER:-}"
[ -n "$SUDO_USER_NAME" ] && usermod -aG docker "$SUDO_USER_NAME" || true
docker volume create trivy-cache >/dev/null
ok "$(docker --version)"

if [ "$FAMILY" = "fedora" ] && systemctl is-active --quiet firewalld; then
  for port in 8080 9000 8081 9090 3000 8089; do firewall-cmd --permanent --add-port=${port}/tcp >/dev/null; done
  firewall-cmd --reload >/dev/null
  ok "Ports ouverts dans firewalld"
fi

# ---------------------------------------------------------------------
# 3. Outils : SonarQube, Nexus, Prometheus, Grafana
# ---------------------------------------------------------------------
log "3/9 Demarrage de SonarQube, Nexus, Prometheus, Grafana"
mkdir -p "$INFRA_DIR"

cat > "$INFRA_DIR/docker-compose-infra.yml" <<'EOF'
services:
  sonarqube:
    image: sonarqube:community
    container_name: sonarqube
    restart: unless-stopped
    ports: ["9000:9000"]
    environment:
      SONAR_VALIDATEWEBHOOKS: "false"    # autorise le webhook vers Jenkins sur l'hote
    extra_hosts: ["host.docker.internal:host-gateway"]
    volumes:
      - sonar_data:/opt/sonarqube/data
      - sonar_extensions:/opt/sonarqube/extensions
  nexus:
    image: sonatype/nexus3
    container_name: nexus
    restart: unless-stopped
    ports: ["8081:8081"]
    volumes:
      - nexus_data:/nexus-data
  prometheus:
    image: prom/prometheus
    container_name: prometheus
    restart: unless-stopped
    ports: ["9090:9090"]
    extra_hosts: ["host.docker.internal:host-gateway"]
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro,z
      - ./alert-rules.yml:/etc/prometheus/alert-rules.yml:ro,z
  grafana:
    image: grafana/grafana
    container_name: grafana
    restart: unless-stopped
    ports: ["3000:3000"]
    volumes:
      - grafana_data:/var/lib/grafana
volumes:
  sonar_data: {}
  sonar_extensions: {}
  nexus_data: {}
  grafana_data: {}
EOF

cat > "$INFRA_DIR/prometheus.yml" <<'EOF'
global:
  scrape_interval: 15s
rule_files:
  - "alert-rules.yml"
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: jenkins
    metrics_path: /prometheus/
    static_configs:
      - targets: ["host.docker.internal:8080"]
  - job_name: achat-app
    metrics_path: /SpringMVC/actuator/prometheus
    static_configs:
      - targets: ["host.docker.internal:8089"]
EOF

cat > "$INFRA_DIR/alert-rules.yml" <<'EOF'
groups:
  - name: devsecops-operations
    rules:
      - alert: CibleMonitoringDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Cible {{ $labels.job }} injoignable ({{ $labels.instance }})"
          description: "Jenkins, l application ou un exporter ne repond plus depuis 1 minute."
EOF

docker compose -f "$INFRA_DIR/docker-compose-infra.yml" up -d
ok "Conteneurs lances"

# ---------------------------------------------------------------------
# 4. Jenkins (installe mais pas encore demarre avec sa config finale)
# ---------------------------------------------------------------------
log "4/9 Installation de Jenkins"
if ! id jenkins >/dev/null 2>&1; then
  if [ "$FAMILY" = "fedora" ]; then
    curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.repo -o /etc/yum.repos.d/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins
  else
    wget -q -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
      > /etc/apt/sources.list.d/jenkins.list
    apt-get update -y
    apt-get install -y jenkins
  fi
fi
systemctl stop jenkins || true
usermod -aG docker jenkins

log "Installation des plugins Jenkins"
JENKINS_WAR="/usr/share/java/jenkins.war"
[ -f "$JENKINS_WAR" ] || JENKINS_WAR="/usr/share/jenkins/jenkins.war"
PM_URL="$(curl -s https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest \
  | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -n1)"
wget -q -O /opt/jenkins-plugin-manager.jar "$PM_URL"
mkdir -p /var/lib/jenkins/plugins
java -jar /opt/jenkins-plugin-manager.jar --war "$JENKINS_WAR" \
  --plugin-download-directory /var/lib/jenkins/plugins \
  --plugins configuration-as-code job-dsl workflow-aggregator git github \
            sonar htmlpublisher email-ext junit credentials-binding \
            pipeline-stage-view prometheus timestamper
chown -R jenkins:jenkins /var/lib/jenkins/plugins
ok "Plugins installes"

# ---------------------------------------------------------------------
# 5. SonarQube : mot de passe, token, webhook
# ---------------------------------------------------------------------
log "5/9 Configuration de SonarQube (attente du demarrage, 2 a 5 min)"
for i in $(seq 1 90); do
  STATUS="$(curl -s http://localhost:9000/api/system/status | jq -r '.status' 2>/dev/null || true)"
  [ "$STATUS" = "UP" ] && break
  sleep 10
done
[ "$STATUS" = "UP" ] || { echo "SonarQube ne demarre pas : docker logs sonarqube"; exit 1; }

curl -s -o /dev/null -u admin:admin -X POST "http://localhost:9000/api/users/change_password" \
  --data-urlencode "login=admin" --data-urlencode "previousPassword=admin" \
  --data-urlencode "password=$SONAR_ADMIN_PASSWORD" || true
curl -s -o /dev/null -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "http://localhost:9000/api/user_tokens/revoke" \
  --data-urlencode "name=jenkins" || true
SONAR_TOKEN="$(curl -s -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "http://localhost:9000/api/user_tokens/generate" \
  --data-urlencode "name=jenkins" --data-urlencode "type=GLOBAL_ANALYSIS_TOKEN" | jq -r '.token' || true)"
[ -n "$SONAR_TOKEN" ] && [ "$SONAR_TOKEN" != "null" ] || { echo "Echec creation token SonarQube"; exit 1; }
curl -s -o /dev/null -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "http://localhost:9000/api/webhooks/create" \
  --data-urlencode "name=jenkins" \
  --data-urlencode "url=http://host.docker.internal:8080/sonarqube-webhook/" || true
ok "Token cree et webhook vers Jenkins configure"

# ---------------------------------------------------------------------
# 6. Nexus : mot de passe admin + settings.xml de Jenkins
# ---------------------------------------------------------------------
log "6/9 Configuration de Nexus (attente du demarrage, 2 a 5 min)"
for i in $(seq 1 90); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/service/rest/v1/status || true)"
  [ "$CODE" = "200" ] && docker exec nexus test -f /nexus-data/admin.password && break
  sleep 10
done
if docker exec nexus test -f /nexus-data/admin.password; then
  NEXUS_INIT="$(docker exec nexus cat /nexus-data/admin.password)"
  curl -s -o /dev/null -u "admin:$NEXUS_INIT" -X PUT \
    "http://localhost:8081/service/rest/v1/security/users/admin/change-password" \
    -H "Content-Type: text/plain" -d "$NEXUS_ADMIN_PASSWORD" || true
  ok "Mot de passe admin Nexus change"
else
  warn "Mot de passe initial Nexus introuvable : connectez-vous a http://$VM_IP:8081 et mettez a jour /var/lib/jenkins/.m2/settings.xml"
fi

mkdir -p /var/lib/jenkins/.m2
cat > /var/lib/jenkins/.m2/settings.xml <<EOF
<settings>
  <servers>
    <server><id>nexus-releases</id><username>admin</username><password>$NEXUS_ADMIN_PASSWORD</password></server>
    <server><id>nexus-snapshots</id><username>admin</username><password>$NEXUS_ADMIN_PASSWORD</password></server>
  </servers>
</settings>
EOF
chmod 600 /var/lib/jenkins/.m2/settings.xml
chown -R jenkins:jenkins /var/lib/jenkins/.m2

# ---------------------------------------------------------------------
# 7. Configuration Jenkins as Code : admin, credentials, SonarQube, job
# ---------------------------------------------------------------------
log "7/9 Configuration automatique de Jenkins (JCasC)"
mkdir -p /var/lib/jenkins/casc_configs
cat > /var/lib/jenkins/casc_configs/jenkins.yaml <<EOF
jenkins:
  systemMessage: "Pipeline DevSecOps - projet achat"
  numExecutors: 2
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "admin"
          password: "$JENKINS_ADMIN_PASSWORD"
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false
credentials:
  system:
    domainCredentials:
      - credentials:
          - string:
              scope: GLOBAL
              id: "sonar-token"
              description: "Token SonarQube"
              secret: "$SONAR_TOKEN"
          - string:
              scope: GLOBAL
              id: "mysql-root-password"
              description: "Mot de passe root MySQL"
              secret: "$MYSQL_ROOT_PASSWORD"
          - usernamePassword:
              scope: GLOBAL
              id: "dockerhub-creds"
              description: "Docker Hub"
              username: "$DOCKERHUB_USER"
              password: "$DOCKERHUB_TOKEN"
unclassified:
  location:
    url: "http://$VM_IP:8080/"
  sonarGlobalConfiguration:
    buildWrapperEnabled: true
    installations:
      - name: "sonarqube"
        serverUrl: "http://localhost:9000"
        credentialsId: "sonar-token"
jobs:
  - script: |
      pipelineJob('$JOB_NAME') {
        description('Pipeline DevSecOps - 4 phases')
        definition {
          cpsScm {
            scm {
              git {
                remote { url('$GITHUB_REPO') }
                branches('*/$GIT_BRANCH')
              }
            }
            scriptPath('Jenkinsfile')
          }
        }
      }
EOF
chmod 600 /var/lib/jenkins/casc_configs/jenkins.yaml
chown -R jenkins:jenkins /var/lib/jenkins/casc_configs

mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<'EOF'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yaml"
TimeoutStartSec=600
EOF
systemctl daemon-reload
systemctl enable jenkins
systemctl restart jenkins

for i in $(seq 1 60); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' -u "admin:$JENKINS_ADMIN_PASSWORD" http://localhost:8080/api/json || true)"
  [ "$CODE" = "200" ] && break
  sleep 5
done
[ "$CODE" = "200" ] && ok "Jenkins pret" || warn "Jenkins repond mal : sudo journalctl -u jenkins -n 100"

# ---------------------------------------------------------------------
# 8. Images des scanners (evite l'attente pendant le build et la demo)
# ---------------------------------------------------------------------
log "8/9 Telechargement des images des scanners"
for img in zricethezav/gitleaks:latest semgrep/semgrep aquasec/trivy:latest hadolint/hadolint \
           ghcr.io/zaproxy/zaproxy:stable docker/docker-bench-security alpine \
           mysql:8.0 eclipse-temurin:17-jre-alpine; do
  docker pull -q "$img" || warn "echec pull $img"
done

# ---------------------------------------------------------------------
# 9. Premier build + recapitulatif
# ---------------------------------------------------------------------
log "9/9 Lancement du premier build"
COOKIES="$(mktemp)"
CRUMB="$(curl -s -c "$COOKIES" -u "admin:$JENKINS_ADMIN_PASSWORD" \
  http://localhost:8080/crumbIssuer/api/json | jq -r '.crumbRequestField + ":" + .crumb' || true)"
if curl -s -o /dev/null -w '%{http_code}' -b "$COOKIES" -u "admin:$JENKINS_ADMIN_PASSWORD" \
     -H "$CRUMB" -X POST "http://localhost:8080/job/$JOB_NAME/build" | grep -qE "^(200|201)$"; then
  ok "Build lance"
else
  warn "Build non lance automatiquement : cliquez sur 'Build Now' dans le job $JOB_NAME"
fi
rm -f "$COOKIES"

cat > "$CRED_FILE" <<EOF
=== Identifiants DevSecOps (fichier lisible par root uniquement) ===
Jenkins    : http://$VM_IP:8080   admin / $JENKINS_ADMIN_PASSWORD
SonarQube  : http://$VM_IP:9000   admin / $SONAR_ADMIN_PASSWORD
Nexus      : http://$VM_IP:8081   admin / $NEXUS_ADMIN_PASSWORD
Grafana    : http://$VM_IP:3000   admin / admin (a changer a la premiere connexion)
Prometheus : http://$VM_IP:9090
Application: http://$VM_IP:8089/SpringMVC/   (apres un build reussi)
MySQL root : $MYSQL_ROOT_PASSWORD (injecte par Jenkins, ne pas commiter)
Job        : http://$VM_IP:8080/job/$JOB_NAME/
EOF
chmod 600 "$CRED_FILE"

echo
cat "$CRED_FILE"
echo
echo "Identifiants enregistres dans $CRED_FILE (relire avec : sudo cat $CRED_FILE)"
echo "Premier build : 15 a 25 min. Suivez-le dans Jenkins > $JOB_NAME > Console Output."
