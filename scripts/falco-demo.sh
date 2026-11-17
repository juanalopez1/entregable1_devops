#!/usr/bin/env bash
# ============================================================
# Dispara una alerta de Falco SIN abrir una shell:
# desde un pod de prueba se hace una conexión al API Server de Kubernetes
# (lo que haría un atacante para explorar el cluster desde un contenedor).
# Falco la detecta con la regla "Unexpected connection to K8s API Server from container".
# La alerta se guarda en reports/falco-event.log
# ============================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

kubectl apply -f k8s/falco-shell-test.yaml
kubectl wait --for=condition=Ready pod/falco-shell-test --timeout=120s

echo "==> Acción sospechosa: conexión al API Server desde el contenedor"
kubectl exec falco-shell-test -- wget -T 5 --no-check-certificate -qO- https://kubernetes.default.svc/version || true

sleep 5
echo "==> Alertas de Falco"
ALERT=$(kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=500 | grep "K8s API Server" | tail -1 || true)
echo "$ALERT"

{
  echo "Evento disparador: conexión HTTPS no interactiva desde el pod falco-shell-test al API Server de Kubernetes."
  echo "Comando ejecutado: kubectl exec falco-shell-test -- wget -T 5 --no-check-certificate -qO- https://kubernetes.default.svc/version"
  echo "Descripción: un proceso wget dentro del contenedor intentó conectarse al API Server (TCP/443)."
  echo "Es el comportamiento típico de un atacante que, tras comprometer un contenedor, explora el cluster."
  echo "No se abrió una shell interactiva."
  echo "Alerta de Falco:"
  echo "$ALERT"
} > reports/falco-event.log
echo "==> Guardado en reports/falco-event.log"

kubectl delete pod falco-shell-test --wait=false