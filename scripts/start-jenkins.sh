#!/usr/bin/env bash
# ============================================================
# Construye y levanta Jenkins en Docker, conectado a Minikube.
#
# Uso (desde la raíz del repo, en Git Bash o WSL):
#   ./scripts/start-jenkins.sh
#
# Requisitos: Docker Desktop encendido y Minikube corriendo.
# ============================================================
set -euo pipefail

# En Git Bash (Windows) evita que las rutas tipo /var/run/... se conviertan a rutas de Windows
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")/.."

IMAGE="todo-jenkins:1.0.0"
NAME="jenkins"
PORT="${JENKINS_PORT:-8090}"
KUBECONFIG_OUT="jenkins/minikube.kubeconfig"

echo "==> 1/5 Construyendo la imagen de Jenkins ($IMAGE)"
docker build -t "$IMAGE" ./jenkins

echo "==> 2/5 Detectando el grupo dueño del socket de Docker"
SOCK_GID=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock alpine:3.20 stat -c %g /var/run/docker.sock)
echo "    GID del socket: $SOCK_GID"

echo "==> 3/5 Levantando el contenedor '$NAME' en http://localhost:$PORT"
docker rm -f "$NAME" >/dev/null 2>&1 || true
run_jenkins() {
  docker run -d --name "$NAME" --restart unless-stopped \
    -p "127.0.0.1:${PORT}:8080" \
    -v jenkins-home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$@" "$IMAGE" >/dev/null
}
# Se agrega el usuario jenkins al grupo del socket (no hace falta correr como root)
run_jenkins --group-add "$SOCK_GID"

# Conectar Jenkins a la red de Minikube para que llegue al API server del cluster
docker network connect minikube "$NAME" 2>/dev/null || true

# Verificar que Jenkins pueda usar Docker
sleep 3
if ! docker exec "$NAME" docker version >/dev/null 2>&1; then
  echo "    AVISO: el usuario jenkins no tiene permiso sobre el socket de Docker."
  echo "    Se reinicia el contenedor como root (ver README, 'Problemas encontrados')."
  docker rm -f "$NAME" >/dev/null
  run_jenkins --user root
  docker network connect minikube "$NAME" 2>/dev/null || true
fi

echo "==> 4/5 Generando el kubeconfig para que Jenkins despliegue en Minikube"
MINIKUBE_IP=$(minikube ip)
kubectl config view --flatten --minify --context minikube \
  | sed -E "s#server: https://[^ ]+#server: https://${MINIKUBE_IP}:8443#" > "$KUBECONFIG_OUT"
echo "    Archivo: $KUBECONFIG_OUT  (NO se sube a git; se carga en Jenkins como credencial)"

# Probar el acceso al cluster desde adentro de Jenkins
docker cp "$KUBECONFIG_OUT" "$NAME":/tmp/kubeconfig-test
if docker exec "$NAME" kubectl --kubeconfig /tmp/kubeconfig-test get nodes; then
  echo "    Jenkins llega al cluster de Minikube"
else
  echo "    AVISO: Jenkins no pudo conectarse a Minikube"
fi
docker exec -u root "$NAME" rm -f /tmp/kubeconfig-test

echo "==> 5/5 Esperando a que Jenkins arranque"
until curl -sf -o /dev/null "http://localhost:${PORT}/login"; do sleep 3; done

echo ""
echo "Jenkins listo en: http://localhost:${PORT}"
if docker exec "$NAME" test -f /var/jenkins_home/secrets/initialAdminPassword; then
  echo "Contraseña inicial de administrador:"
  docker exec "$NAME" cat /var/jenkins_home/secrets/initialAdminPassword
fi
echo ""
echo "Versiones de las herramientas dentro de Jenkins:"
docker exec "$NAME" sh -c 'docker --version; kubectl version --client | head -1; helm version --short; snyk --version; semgrep --version; python3 --version; mvn -v | head -1'
