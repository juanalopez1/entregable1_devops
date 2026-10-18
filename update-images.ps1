
# para ejecutar cada vez que se cambien los apps y se quieran actualizar las imágenes en minikube
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [string]$Description,
        [scriptblock]$Command
    )

    Write-Host "`n=== $Description ===" -ForegroundColor Cyan

    & $Command

    if ($LASTEXITCODE -ne 0) {
        throw "Error durante el paso: $Description"
    }
}

# 1. Construir las imágenes
Invoke-Step "Construyendo imagen BLUE" {
    docker build --no-cache -t todo-app:blue .
}

Invoke-Step "Construyendo imagen GREEN" {
    docker build --no-cache -f Dockerfile.green -t todo-app:green .
}

# 2. Cargar las imágenes en Minikube
Invoke-Step "Actualizando imagen BLUE en Minikube" {
    minikube image load todo-app:blue --overwrite
}

Invoke-Step "Actualizando imagen GREEN en Minikube" {
    minikube image load todo-app:green --overwrite
}

# 3. Reiniciar los Deployments
Invoke-Step "Reiniciando BLUE" {
    kubectl rollout restart deployment/todo-blue
}

Invoke-Step "Reiniciando GREEN" {
    kubectl rollout restart deployment/todo-green
}

# 4. Esperar a que los nuevos Pods estén listos
Invoke-Step "Verificando BLUE" {
    kubectl rollout status deployment/todo-blue --timeout=120s
}

Invoke-Step "Verificando GREEN" {
    kubectl rollout status deployment/todo-green --timeout=120s
}

Write-Host "`n¡Las dos versiones fueron actualizadas!" -ForegroundColor Green

kubectl get pods
