#!/usr/bin/env bash
# ============================================================
# Abre los accesos locales a la app, Grafana y Prometheus.
# Queda corriendo; Ctrl+C cierra todos.
# ============================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1

kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8082:80 >/dev/null &
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 >/dev/null &
kubectl port-forward -n monitoring svc/monitoring-prometheus 9090:9090 >/dev/null &
trap 'kill $(jobs -p) 2>/dev/null' EXIT

echo "App:        http://todo.local:8082"
echo "Grafana:    http://localhost:3000"
echo "Prometheus: http://localhost:9090"
echo "(Ctrl+C para cerrar)"
wait