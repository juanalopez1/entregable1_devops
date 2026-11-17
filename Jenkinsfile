// ============================================================
// Pipeline CI/CD - Entregable 4
// Clonar -> Semgrep -> Snyk -> Build & Test -> Docker (scan + push) -> Helm
// ============================================================
pipeline {
    agent any

    parameters {
        choice(name: 'DEPLOY_TARGET', choices: ['minikube', 'ucu'],
               description: 'Cluster donde se despliega (minikube local o cluster de la UCU)')
        choice(name: 'ENVIRONMENT', choices: ['dev', 'prod'],
               description: 'Archivo de valores de Helm (values-dev.yaml o values-prod.yaml)')
    }

    environment {
        REGISTRY_USER = 'juanalopez1'
        APP_IMAGE     = "${REGISTRY_USER}/todo-app"
        MONITOR_IMAGE = "${REGISTRY_USER}/todo-monitor"
        // Cada ejecución publica una versión nueva: 1.0.<número de build>
        VERSION       = "1.0.${BUILD_NUMBER}"
        REPORTS       = 'reports/pipeline'
        // Token de Snyk (credencial de Jenkins); en el log aparece como ****
        SNYK_TOKEN    = credentials('snyk-token')
    }

    options {
        skipDefaultCheckout()          // la clonación se hace en la etapa 1, explícita
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {

        stage('1. Clonar repositorio') {
            steps {
                checkout scm
                sh 'git log -1 --oneline'
                sh 'mkdir -p "$REPORTS"'
            }
        }

        stage('2. Análisis estático (Semgrep)') {
            steps {
                // Reglas de seguridad para Python y Flask del registro de Semgrep.
                // --error: el pipeline falla si hay hallazgos de severidad ERROR.
                sh '''
                    semgrep scan \
                      --config p/python \
                      --config p/flask \
                      --severity ERROR \
                      --error \
                      --metrics=off \
                      --text-output="$REPORTS/semgrep.txt" \
                      app.py monitor_client.py
                '''
            }
        }

        stage('3. Dependencias (Snyk)') {
            steps {
                // Flask: Snyk necesita las dependencias instaladas para analizarlas
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --quiet -r requirements-dev.txt

                    set +e
                    snyk test --file=requirements.txt --package-manager=pip \
                      --severity-threshold=critical > "$REPORTS/snyk-app-deps.txt" 2>&1
                    rc=$?
                    cat "$REPORTS/snyk-app-deps.txt"
                    exit $rc
                '''
                // Monitor: dependencias de Maven (pom.xml).
                // monitor/.snyk documenta la vulnerabilidad crítica aceptada.
                sh '''
                    set +e
                    snyk test --file=monitor/pom.xml --policy-path=monitor \
                      --severity-threshold=critical > "$REPORTS/snyk-monitor-deps.txt" 2>&1
                    rc=$?
                    cat "$REPORTS/snyk-monitor-deps.txt"
                    exit $rc
                '''
            }
        }

        stage('4. Build & Test') {
            steps {
                // Flask: tests unitarios con pytest
                sh '''
                    . .venv/bin/activate
                    pytest -v --junitxml="$REPORTS/pytest.xml"
                '''
                // Monitor: compilación y tests con Maven
                sh 'mvn -B -q -f monitor/pom.xml verify'
            }
        }

        stage('5. Docker: build, escaneo y publicación') {
            steps {
                sh '''
                    docker build -t "$APP_IMAGE:$VERSION" .
                    docker build -t "$MONITOR_IMAGE:$VERSION" ./monitor
                '''
                // Antes de publicar: las imágenes no pueden tener vulnerabilidades críticas nuevas
                // (.snyk y monitor/.snyk documentan las aceptadas)
                sh '''
                    set +e
                    snyk container test "$APP_IMAGE:$VERSION" --file=Dockerfile --policy-path=. \
                      --severity-threshold=critical > "$REPORTS/snyk-app-image.txt" 2>&1
                    rc1=$?
                    snyk container test "$MONITOR_IMAGE:$VERSION" --file=monitor/Dockerfile --policy-path=monitor \
                      --severity-threshold=critical > "$REPORTS/snyk-monitor-image.txt" 2>&1
                    rc2=$?
                    tail -n 25 "$REPORTS/snyk-app-image.txt" "$REPORTS/snyk-monitor-image.txt"
                    [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]
                '''
                withCredentials([usernamePassword(credentialsId: 'dockerhub',
                                                  usernameVariable: 'DOCKERHUB_USER',
                                                  passwordVariable: 'DOCKERHUB_TOKEN')]) {
                    sh '''
                        echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
                        docker push "$APP_IMAGE:$VERSION"
                        docker push "$MONITOR_IMAGE:$VERSION"
                    '''
                }
            }
        }

        stage('6. Deploy en Kubernetes (Helm)') {
            steps {
                script {
                    def kubeCredential = params.DEPLOY_TARGET == 'ucu' ? 'kubeconfig-ucu' : 'kubeconfig-minikube'
                    withCredentials([file(credentialsId: kubeCredential, variable: 'KUBECONFIG')]) {
                        sh '''
                            helm upgrade --install todo-app ./helm-chart \
                              -f "helm-chart/values-$ENVIRONMENT.yaml" \
                              --set image.repository="$APP_IMAGE" \
                              --set image.tag="$VERSION" \
                              --set monitor.image.repository="$MONITOR_IMAGE" \
                              --set monitor.image.tag="$VERSION" \
                              --wait --timeout 5m

                            helm history todo-app --max 5
                            kubectl get pods,svc,ingress -o wide
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'reports/pipeline/**', allowEmptyArchive: true
            sh 'docker logout || true'
            cleanWs()
        }
        success {
            echo "Desplegada la versión ${VERSION} en ${params.DEPLOY_TARGET} (${params.ENVIRONMENT})"
        }
        failure {
            echo 'El pipeline falló: revisar la etapa marcada en rojo y los reportes archivados.'
        }
    }
}
