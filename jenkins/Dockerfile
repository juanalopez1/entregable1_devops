# ============================================================
# Imagen de Jenkins con todas las herramientas del pipeline
# (versiones fijas para que el CI sea reproducible)
# ============================================================
FROM jenkins/jenkins:2.580.2-lts-jdk21

# Versiones de las herramientas
ARG DOCKER_VERSION=28.5.1
ARG KUBECTL_VERSION=v1.35.1
ARG HELM_VERSION=v4.2.0
ARG SNYK_VERSION=1.1306.4
ARG SEMGREP_VERSION=1.183.0

# Para instalar paquetes hace falta root; al final se vuelve al usuario jenkins
USER root

# Python (tests de Flask y Semgrep) y Maven (build del monitor y Snyk sobre pom.xml)
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv python3-pip maven curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (solo el cliente: usa el Docker de la máquina a través del socket)
RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
    | tar -xz --strip-components=1 -C /usr/local/bin docker/docker

# kubectl (misma versión que el cluster de Minikube)
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# Helm
RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar -xz --strip-components=1 -C /usr/local/bin linux-amd64/helm

# Snyk CLI (binario oficial)
RUN curl -fsSL -o /usr/local/bin/snyk "https://downloads.snyk.io/cli/v${SNYK_VERSION}/snyk-linux" \
    && chmod +x /usr/local/bin/snyk

# Semgrep, en su propio entorno virtual de Python
RUN python3 -m venv /opt/semgrep \
    && /opt/semgrep/bin/pip install --no-cache-dir "semgrep==${SEMGREP_VERSION}" \
    && ln -s /opt/semgrep/bin/semgrep /usr/local/bin/semgrep

# Jenkins corre con su usuario sin privilegios
USER jenkins

# Plugins necesarios para el pipeline
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
