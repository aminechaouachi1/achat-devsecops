// =====================================================================
// Pipeline DevSecOps - projet "achat" (Spring Boot / Maven / MySQL)
// Base : pipeline DevOps 4e annee (Git, Maven, SonarQube, Nexus,
//        Docker, Docker Compose, Prometheus/Grafana)
// Ajouts : securite sur les 4 phases Development / Acceptance /
//          Production / Operations
// Aucune valeur a adapter : comptes et secrets viennent des credentials Jenkins
// =====================================================================
pipeline {
    agent any

    parameters {
        booleanParam(name: 'BLOCK_ON_FINDINGS', defaultValue: false,
            description: 'true = une vuln HIGH/CRITICAL ou un secret fait echouer le build (sinon build UNSTABLE)')
    }

    environment {
        APP_NAME     = 'achat'
        IMAGE        = "${APP_NAME}"                   // image locale ; le compte Docker Hub vient du credential
        TAG          = "${BUILD_NUMBER}"
        APP_URL      = 'http://localhost:8089/SpringMVC/'
        REPORTS      = 'security-reports'
        TRIVY_CACHE  = 'trivy-cache'                    // volume Docker pour la base Trivy
    }

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '15'))
        timeout(time: 60, unit: 'MINUTES')
    }

    stages {

        // =============================================================
        // Initialisation
        // =============================================================
        stage('Checkout') {
            steps {
                checkout scm
                // les scanners tournent en root dans Docker : nettoyage via un conteneur
                sh '''
                    docker run --rm -v "$WORKSPACE:/w" alpine rm -rf /w/$REPORTS
                    mkdir -p $REPORTS && chmod 777 $REPORTS
                '''
            }
        }

        // =============================================================
        // PHASE 1 - DEVELOPMENT
        // =============================================================
        stage('P1 - Secrets scan (Gitleaks)') {
            steps {
                script {
                    def rc = sh(returnStatus: true, script: '''
                        docker run --rm -v "$WORKSPACE:/repo" zricethezav/gitleaks:latest \
                          detect --source=/repo --redact \
                          --report-format=json --report-path=/repo/$REPORTS/gitleaks-report.json
                    ''')
                    handleFindings(rc, 'Gitleaks : secret(s) detecte(s)')
                }
            }
        }

        stage('P1 - Build & Tests unitaires') {
            steps {
                sh 'mvn clean verify'   // compile + tests JUnit (+ JaCoCo si configure dans le pom)
            }
            post {
                always { junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml' }
            }
        }

        stage('P1 - SAST (SonarQube)') {
            steps {
                withSonarQubeEnv('sonarqube') {   // nom du serveur dans Manage Jenkins > System
                    sh 'mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar -Dsonar.projectKey=$APP_NAME -Dsonar.projectName=$APP_NAME'
                }
            }
        }

        stage('P1 - SAST complementaire (Semgrep)') {
            steps {
                script {
                    def rc = sh(returnStatus: true, script: '''
                        docker run --rm -v "$WORKSPACE:/src" -w /src semgrep/semgrep \
                          semgrep scan --config p/java --config p/secrets \
                          --json --output $REPORTS/semgrep-report.json --error
                    ''')
                    handleFindings(rc, 'Semgrep : regle(s) de securite violee(s)')
                }
            }
        }

        stage('P1 - SCA dependances (Trivy fs)') {
            steps {
                script {
                    def rc = sh(returnStatus: true, script: '''
                        docker run --rm -v "$WORKSPACE:/src" -v $TRIVY_CACHE:/root/.cache/ aquasec/trivy:latest \
                          fs --scanners vuln --severity HIGH,CRITICAL \
                          --format table --output /src/$REPORTS/trivy-sca-report.txt /src
                        docker run --rm -v "$WORKSPACE:/src" -v $TRIVY_CACHE:/root/.cache/ aquasec/trivy:latest \
                          fs --scanners vuln --format json --output /src/$REPORTS/trivy-sca-report.json \
                          --severity HIGH,CRITICAL --exit-code 1 /src
                    ''')
                    handleFindings(rc, 'Trivy SCA : dependance(s) vulnerable(s) HIGH/CRITICAL')
                }
            }
        }

        // =============================================================
        // PHASE 2 - ACCEPTANCE
        // =============================================================
        stage('P2 - Lint Dockerfile (Hadolint)') {
            steps {
                script {
                    def rc = sh(returnStatus: true, script: '''
                        rc=0
                        docker run --rm -i hadolint/hadolint < Dockerfile > $REPORTS/hadolint-report.txt || rc=$?
                        cat $REPORTS/hadolint-report.txt
                        exit $rc
                    ''')
                    handleFindings(rc, 'Hadolint : mauvaises pratiques dans le Dockerfile')
                }
            }
        }

        stage('P2 - IaC scan (Trivy config)') {
            steps {
                script {
                    def rc = sh(returnStatus: true, script: '''
                        docker run --rm -v "$WORKSPACE:/src" -v $TRIVY_CACHE:/root/.cache/ aquasec/trivy:latest \
                          config --severity HIGH,CRITICAL --exit-code 1 \
                          --format table --output /src/$REPORTS/trivy-iac-report.txt /src
                    ''')
                    handleFindings(rc, 'Trivy IaC : mauvaise configuration (Dockerfile et fichiers IaC)')
                }
            }
        }

        stage('P2 - Build image Docker') {
            steps {
                sh 'docker build -t $IMAGE:$TAG -t $IMAGE:latest .'
            }
        }

        stage('P2 - Scan image (Trivy image)') {
            steps {
                script {
                    def rc = sh(returnStatus: true, script: '''
                        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                          -v "$WORKSPACE:/src" -v $TRIVY_CACHE:/root/.cache/ aquasec/trivy:latest \
                          image --severity HIGH,CRITICAL --format table \
                          --output /src/$REPORTS/trivy-image-report.txt $IMAGE:$TAG
                        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                          -v "$WORKSPACE:/src" -v $TRIVY_CACHE:/root/.cache/ aquasec/trivy:latest \
                          image --severity HIGH,CRITICAL --exit-code 1 --format json \
                          --output /src/$REPORTS/trivy-image-report.json $IMAGE:$TAG
                    ''')
                    handleFindings(rc, 'Trivy image : vulnerabilite(s) HIGH/CRITICAL dans l image')
                }
            }
        }

        stage('P2 - Deploiement recette (Docker Compose)') {
            steps {
                withCredentials([string(credentialsId: 'mysql-root-password', variable: 'MYSQL_ROOT_PASSWORD')]) {
                    sh '''
                        export TAG=$TAG IMAGE=$IMAGE MYSQL_ROOT_PASSWORD
                        docker compose down || true
                        docker compose up -d
                    '''
                }
                // attendre que l application reponde (max ~3 min)
                sh '''
                    for i in $(seq 1 36); do
                      curl -s -o /dev/null "$APP_URL" && echo "Application UP" && exit 0
                      sleep 5
                    done
                    echo "Application non joignable" && exit 1
                '''
            }
        }

        stage('P2 - DAST (OWASP ZAP baseline)') {
            steps {
                script {
                    def rc = sh(returnStatus: true, script: '''
                        docker run --rm --network host -v "$WORKSPACE/$REPORTS:/zap/wrk:rw" \
                          ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t "$APP_URL" \
                          -r zap-report.html -J zap-report.json -I
                    ''')
                    handleFindings(rc, 'OWASP ZAP : alerte(s) sur l application deployee')
                }
            }
        }

        // =============================================================
        // PHASE 3 - PRODUCTION
        // =============================================================
        stage('P3 - Quality Gate SonarQube') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true   // necessite le webhook SonarQube -> Jenkins
                }
            }
        }

        stage('P3 - SBOM (CycloneDX via Trivy)') {
            steps {
                sh '''
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                      -v "$WORKSPACE:/src" -v $TRIVY_CACHE:/root/.cache/ aquasec/trivy:latest \
                      image --format cyclonedx --output /src/$REPORTS/sbom-cyclonedx.json $IMAGE:$TAG
                '''
            }
        }

        stage('P3 - Publication Nexus') {
            steps {
                sh 'mvn deploy -DskipTests'   // distributionManagement du pom + /var/lib/jenkins/.m2/settings.xml
            }
        }

        stage('P3 - Push image (Docker Hub)') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker tag $IMAGE:$TAG $DH_USER/$IMAGE:$TAG
                        docker tag $IMAGE:$TAG $DH_USER/$IMAGE:latest
                        docker push $DH_USER/$IMAGE:$TAG
                        docker push $DH_USER/$IMAGE:latest
                        docker logout
                    '''
                }
            }
        }

        // =============================================================
        // PHASE 4 - OPERATIONS
        // =============================================================
        stage('P4 - Audit hote Docker (Docker Bench Security)') {
            steps {
                sh '''
                    docker run --rm --net host --pid host --userns host --cap-add audit_control \
                      -v /etc:/etc:ro -v /var/lib:/var/lib:ro \
                      -v /var/run/docker.sock:/var/run/docker.sock:ro \
                      --label docker_bench_security docker/docker-bench-security \
                      > $REPORTS/docker-bench-report.txt 2>&1 || true
                    grep -c "\\[WARN\\]" $REPORTS/docker-bench-report.txt || true
                '''
            }
        }

        stage('P4 - Verification monitoring (Prometheus)') {
            steps {
                sh '''
                    curl -s http://localhost:9090/api/v1/targets > $REPORTS/prometheus-targets.json || true
                    curl -s http://localhost:9090/api/v1/rules   > $REPORTS/prometheus-rules.json   || true
                '''
            }
        }
    }

    // =================================================================
    // Conservation des rapports + notification
    // =================================================================
    post {
        always {
            archiveArtifacts artifacts: "${REPORTS}/**", allowEmptyArchive: true, fingerprint: true
            publishHTML(target: [reportDir: "${REPORTS}", reportFiles: 'zap-report.html',
                                 reportName: 'OWASP ZAP Report', keepAll: true,
                                 alwaysLinkToLastBuild: true, allowMissing: true])
        }
        failure {
            emailext subject: "[DevSecOps] ECHEC ${JOB_NAME} #${BUILD_NUMBER}",
                     body: "Le pipeline a echoue. Rapports : ${BUILD_URL}artifact/${REPORTS}/",
                     to: 'aminechaouachi30@gmail.com'
        }
        unstable {
            emailext subject: "[DevSecOps] Vulnerabilites detectees ${JOB_NAME} #${BUILD_NUMBER}",
                     body: "Des failles ont ete detectees. Rapports : ${BUILD_URL}artifact/${REPORTS}/",
                     to: 'aminechaouachi30@gmail.com'
        }
    }
}

// Code retour != 0 d un scanner : FAILURE si BLOCK_ON_FINDINGS, sinon UNSTABLE
def handleFindings(int rc, String message) {
    if (rc != 0) {
        if (params.BLOCK_ON_FINDINGS) {
            error(message)
        } else {
            unstable(message)
        }
    }
}
