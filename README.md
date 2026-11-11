# achat - Pipeline DevSecOps

Application Spring Boot 3 (Java 17, MySQL) et pipeline Jenkins DevSecOps sur 4 phases :
Development, Acceptance, Production, Operations.

Depot : https://github.com/aminechaouachi1/achat-devsecops

## Contenu

| Chemin | Role |
| --- | --- |
| `src/` | Application REST : `/SpringMVC/produits`, `/SpringMVC/fournisseurs`, Actuator |
| `Jenkinsfile` | Pipeline DevSecOps (18 stages) |
| `Dockerfile` | Image durcie (JRE Alpine, non-root, healthcheck) |
| `docker-compose.yml` | Deploiement durci app + MySQL |
| `infra/setup-devsecops.sh` | Installation et configuration automatiques (Kali, Debian, Ubuntu, Fedora) |
| `infra/Vagrantfile` | VM Ubuntu 22.04 (optionnel) |

## Installation sur Kali, Debian, Ubuntu ou Fedora (8 Go de RAM conseilles)

```bash
git clone https://github.com/aminechaouachi1/achat-devsecops.git
sudo bash achat-devsecops/infra/setup-devsecops.sh
```

Le script demande l identifiant et un access token Docker Hub, puis installe et configure
Jenkins, SonarQube, Nexus, Prometheus et Grafana, cree le job et lance le premier build.
Les identifiants generes sont dans /root/devsecops-identifiants.txt.
