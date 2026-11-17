#!/usr/bin/env bash
# ============================================================
# Levanta TODO el entorno del entregable 4 en Minikube:
#   cluster + Ingress + operadores (Prometheus Operator, Kyverno, Falco)
#   + políticas + dashboard + aplicación (Flask + monitor)
#
# Uso (desde la raíz del repo, en Git Bash o WSL):
#   ./scripts/setup.sh
#   GRAFANA_PASSWORD=miClave APP_TAG=1.0.12 ./scripts/setup.sh
#
# Variables opcionales:
#   GRAFANA_PASSWORD  clave del usuario admin de Grafana (si no se pasa, se genera una)
#   APP_TAG           versión de las imágenes en Docker Hub (si no se pasa, la más reciente)
# ============================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

REGISTRY_USER="juanalopez1"
KPS_VERSION="87.19.2"      # kube-prometheus-stack
KYVERNO_VERSION="3.9.2"    # Kyverno v1.19.2
FALCO_VERSION="9.0.0"      # Falco

step() { echo; echo "==> $*"; }

step "1/8 Cluster de Minikube"
if ! minikube status >/dev/null 2>&1; then
  minikube start --cpus=4 --memory=6144
fi
kubectl get nodes

step "2/8 Ingress Controller (NGINX)"
minikube addons enable ingress
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

step "3/8 Repositorios de Helm"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update

step "4/8 Operador de monitoreo: kube-prometheus-stack (Prometheus + Grafana + Alertmanager)"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)}"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$KPS_VERSION" -n monitoring --create-namespace \
  -f monitoring/kube-prometheus-stack-values.yaml \
  --set grafana.adminPassword="$GRAFANA_PASSWORD" \
  --wait --timeout 10m

# Dashboard de Grafana como ConfigMap (el sidecar de Grafana lo carga solo)
kubectl create configmap todo-app-dashboard -n monitoring \
  --from-file=todo-app.json=grafana/dashboard.json --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap todo-app-dashboard -n monitoring grafana_dashboard=1 --overwrite

step "5/8 Operador de políticas: Kyverno + 4 políticas"
helm upgrade --install kyverno kyverno/kyverno \
  --version "$KYVERNO_VERSION" -n kyverno --create-namespace --wait --timeout 10m
kubectl apply -f k8s/policies/
kubectl get clusterpolicy

step "6/8 Seguridad en tiempo de ejecución: Falco"
helm upgrade --install falco falcosecurity/falco \
  --version "$FALCO_VERSION" -n falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set tty=true \
  --wait --timeout 10m

step "7/8 Aplicación (Flask + monitor) desde Docker Hub"
if [ -z "${APP_TAG:-}" ]; then
  # Última versión publicada por Jenkins en Docker Hub
  APP_TAG=$(curl -s "https://hub.docker.com/v2/repositories/${REGISTRY_USER}/todo-app/tags?page_size=1&ordering=last_updated" \
    | grep -o '"name": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
fi
echo "    Versión de las imágenes: $APP_TAG"
helm upgrade --install todo-app ./helm-chart \
  -f helm-chart/values-dev.yaml \
  --set image.repository="${REGISTRY_USER}/todo-app" --set image.tag="$APP_TAG" \
  --set monitor.image.repository="${REGISTRY_USER}/todo-monitor" --set monitor.image.tag="$APP_TAG" \
  --wait --timeout 5m

step "8/8 Estado final"
kubectl get pods -A | grep -E "NAMESPACE|default|monitoring|kyverno|falco|ingress-nginx"

cat <<MSG

============================================================
 Entorno listo
============================================================
 Para acceder (dejar corriendo en otra terminal):
   ./scripts/port-forward.sh        # app, Grafana y Prometheus

   App:        http://todo.local:8082   (requiere "127.0.0.1 todo.local" en el archivo hosts)
   Grafana:    http://localhost:3000    usuario: admin   clave: $GRAFANA_PASSWORD
   Prometheus: http://localhost:9090

 Jenkins:          ./scripts/start-jenkins.sh
 Generar tráfico:  ./scripts/load.sh 300
 Prueba de Falco:  ./scripts/falco-demo.sh
 Borrar todo:      ./scripts/teardown.sh
MSG