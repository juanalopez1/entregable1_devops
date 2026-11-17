#!/usr/bin/env bash
# ============================================================
# Borra todos los recursos creados por setup.sh.
#
# Uso:
#   ./scripts/teardown.sh          # borra app, operadores, políticas y namespaces
#   ./scripts/teardown.sh --all    # además borra Jenkins (con su volumen) y el cluster de Minikube
# ============================================================
set -uo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

step() { echo; echo "==> $*"; }

step "Aplicación"
helm uninstall todo-app 2>/dev/null
kubectl delete pod falco-shell-test --ignore-not-found

step "Políticas y Kyverno"
kubectl delete -f k8s/policies/ --ignore-not-found
helm uninstall kyverno -n kyverno 2>/dev/null

step "Falco"
helm uninstall falco -n falco 2>/dev/null

step "Monitoreo (Prometheus, Grafana, Alertmanager)"
helm uninstall monitoring -n monitoring 2>/dev/null
# Los CRDs del Prometheus Operator no se borran con helm uninstall
kubectl get crd -o name | grep monitoring.coreos.com | xargs -r kubectl delete

step "Namespaces"
kubectl delete namespace monitoring kyverno falco --ignore-not-found

if [ "${1:-}" = "--all" ]; then
  step "Jenkins (contenedor y volumen)"
  docker rm -f jenkins 2>/dev/null
  docker volume rm jenkins-home 2>/dev/null

  step "Cluster de Minikube"
  minikube delete
fi

echo; echo "Listo."