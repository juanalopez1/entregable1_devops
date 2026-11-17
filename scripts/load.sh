#!/usr/bin/env bash
# ============================================================
# Genera tráfico contra la aplicación para poblar los dashboards
# de Grafana (RPS, latencia, CPU/memoria y métricas de negocio).
#
# Uso (Git Bash o WSL):
#   ./scripts/load.sh                         # 300 iteraciones contra http://todo.local:8082
#   ./scripts/load.sh 1000                    # más iteraciones
#   APP_URL=http://localhost:8081 ./scripts/load.sh
#
# Requisito: la app accesible (port-forward del Ingress Controller:
#   kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8082:80)
# ============================================================
set -euo pipefail

APP_URL="${APP_URL:-http://todo.local:8082}"
ITERATIONS="${1:-300}"
PRIORITIES=(baja media alta)
COOKIES="$(mktemp)"
trap 'rm -f "$COOKIES"' EXIT

# La app tiene protección CSRF: hay que pedir la página primero (cookie de sesión)
# y mandar el token en cada POST, igual que hace el navegador.
get_page() {
  curl -s -c "$COOKIES" -b "$COOKIES" "$APP_URL/$1"
}
csrf_token() {
  grep -o 'name="csrf_token" value="[^"]*"' | head -1 | sed 's/.*value="//; s/"$//'
}
post() {
  curl -s -o /dev/null -c "$COOKIES" -b "$COOKIES" -X POST "$APP_URL$1" --data-urlencode "csrf_token=$2" "${@:3}"
}

echo "Generando tráfico contra $APP_URL ($ITERATIONS iteraciones)..."
for i in $(seq 1 "$ITERATIONS"); do
  page="$(get_page "")"
  token="$(echo "$page" | csrf_token || true)"

  # Crear una tarea con prioridad al azar
  priority="${PRIORITIES[$((RANDOM % 3))]}"
  post "/add" "$token" --data-urlencode "title=tarea-$i" --data-urlencode "priority=$priority"

  # Navegar con los filtros
  get_page "?filter=pending" >/dev/null
  get_page "?filter=completed" >/dev/null

  # Cada tanto completar o borrar la primera tarea de la lista
  task_id="$(echo "$page" | grep -o 'action="/complete/[0-9]*"' | head -1 | grep -o '[0-9]*' || true)"
  if [ -n "$task_id" ]; then
    if [ $((i % 3)) -eq 0 ]; then post "/complete/$task_id" "$token"; fi
    if [ $((i % 5)) -eq 0 ]; then post "/delete/$task_id" "$token"; fi
  fi

  # Algunas peticiones a rutas inexistentes (para ver errores 404 en el dashboard)
  if [ $((i % 20)) -eq 0 ]; then get_page "no-existe" >/dev/null; fi

  if [ $((i % 50)) -eq 0 ]; then echo "  $i/$ITERATIONS"; fi
done
echo "Listo. Mirá el dashboard 'TaskFlow - Aplicación To-Do' en Grafana."