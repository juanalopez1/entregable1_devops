# Monitor y alertas

Servicio **Java 21 + Spring Boot** que cuenta las operaciones de TaskFlow (crear, completar, eliminar) y las expone para Prometheus.

Grafana muestra el tablero. Prometheus alerta si se crean más de **10 tareas en 5 minutos**.

```text
Usuario
   |
   v
todo-service  (BLUE o GREEN)
   |
   v
Flask
   |
   v
monitor-service :8080
   |
   +---> Prometheus  --->  Alertmanager
           |
           v
        Grafana
```

Los umbrales se calculan en Prometheus. Este servicio solo incrementa el contador `todo_operations_total`.

---

## Qué hay que tener

- Docker Desktop encendido
- Minikube y kubectl (en este proyecto se usaron desde WSL)
- Estar en el contexto de Minikube, no en otro cluster:

```bash
kubectl config use-context minikube
```

O usar siempre:

```bash
kubectl --context=minikube ...
```

---

## 1. Iniciar Minikube

Desde WSL:

```bash
minikube start --driver=docker
```

Verificamos:

```bash
minikube status
kubectl --context=minikube get nodes
```

---

## 2. Construir las imágenes

Desde la raíz del repo.

Monitor:

```bash
docker build -t todo-monitor:1.0 ./monitor
```

Flask tiene que reconstruirse porque avisa cada operación al monitor:

```bash
docker build -t todo-app:blue .
docker build -f Dockerfile.green -t todo-app:green .
```

Cargamos las tres en Minikube (las imágenes son locales, no están en Docker Hub):

```bash
minikube image load todo-monitor:1.0
minikube image load todo-app:blue
minikube image load todo-app:green
```

---

## 3. Desplegar en Kubernetes

App (si todavía no está):

```bash
kubectl --context=minikube apply -f k8s/deployment-blue.yaml
kubectl --context=minikube apply -f k8s/deployment-green.yaml
kubectl --context=minikube apply -f k8s/service.yaml
```

Monitor:

```bash
kubectl --context=minikube apply -f k8s/monitor-deployment.yaml
kubectl --context=minikube apply -f k8s/monitor-service.yaml
```

Prometheus, Grafana y Alertmanager:

```bash
kubectl --context=minikube apply -f k8s/monitoring/
```

Ahí hay un YAML por componente:

```text
k8s/monitoring/prometheus.yaml
k8s/monitoring/grafana.yaml
k8s/monitoring/alertmanager.yaml
```

Si BLUE y GREEN ya existían, reiniciamos para que tomen la imagen nueva:

```bash
kubectl --context=minikube rollout restart deployment/todo-blue
kubectl --context=minikube rollout restart deployment/todo-green
```

Esperamos a que todo quede Running:

```bash
kubectl --context=minikube get pods
```

Deberíamos ver:

```text
todo-blue-...        1/1   Running
todo-green-...       1/1   Running
todo-monitor-...     1/1   Running
prometheus-...       1/1   Running
grafana-...          1/1   Running
alertmanager-...     1/1   Running
```

---

## 4. Abrir las UIs (port-forward)

Con el driver Docker de Minikube, `minikube service` deja la terminal colgada. Es más simple exponer los puertos así. Cada comando necesita su propia terminal y tiene que seguir corriendo.

```bash
kubectl --context=minikube port-forward --address=0.0.0.0 svc/todo-service 5000:80
kubectl --context=minikube port-forward --address=0.0.0.0 svc/prometheus-service 9090:9090
kubectl --context=minikube port-forward --address=0.0.0.0 svc/grafana-service 3000:3000
kubectl --context=minikube port-forward --address=0.0.0.0 svc/alertmanager-service 9093:9093
```

Después, desde el navegador de Windows:

| Qué | URL | Login |
|---|---|---|
| TaskFlow | http://127.0.0.1:5000 | — |
| Prometheus | http://127.0.0.1:9090 | — |
| Grafana | http://127.0.0.1:3000 | `admin` / `admin` |
| Alertmanager | http://127.0.0.1:9093 | — |

Importante: el port-forward de la app se queda pegado al Pod que había cuando se abrió. Si cambiás BLUE ↔ GREEN, cortalo (Ctrl+C) y volvé a levantarlo. Si no, el navegador sigue mostrando la versión anterior.

---

## 5. Cómo usar Grafana

1. Entrar a http://127.0.0.1:3000 con `admin` / `admin`.
2. Menú izquierdo → **Dashboards** → **TaskFlow Operaciones**.
3. El tablero ya viene provisionado. No hay que crear paneles.

Qué mira cada gráfico:

- **Creaciones de tareas (últimos 5 minutos)**: es el panel de la alerta. La línea roja es el umbral de 10.
- **Operaciones por tipo**: `create`, `complete`, `delete`.
- **Creaciones por prioridad**: `none` en BLUE, o `baja` / `media` / `alta` en GREEN.
- **Creaciones por versión**: BLUE o GREEN.

Grafana solo muestra. La alerta la decide Prometheus.

---

## 6. Cómo usar Prometheus

1. Entrar a http://127.0.0.1:9090
2. **Status → Targets**: `todo-monitor` tiene que estar **UP**.
3. **Status → Alerts**: acá se ve si una regla está inactive, pending o firing.
4. En **Graph** se puede pegar:

```text
sum(increase(todo_operations_total{operation="create"}[5m]))
```

Reglas:

```text
TooManyTaskCreations
  más de 10 creaciones en 5 minutos

TooManyHighPriorityCreations
  más de 5 creaciones de prioridad alta en 5 minutos
```

Prometheus scrapea cada 15 segundos. La regla espera 15 segundos más (`for: 15s`) antes de pasar a firing. En total, unos 20–30 segundos después del burst.

---

## 7. Disparar la alerta de creaciones

Con el Service apuntando a BLUE o GREEN, crear 15 tareas. En PowerShell:

```powershell
1..15 | ForEach-Object { curl.exe -s -X POST -d "title=prueba-$_" http://127.0.0.1:5000/add }
```

En WSL / Git Bash:

```bash
for i in $(seq 1 15); do
  curl -s -X POST -d "title=prueba-$i" http://127.0.0.1:5000/add
done
```

También se pueden cargar a mano desde la web.

Después:

1. Grafana → el primer panel cruza el 10.
2. Prometheus → **Status → Alerts** → `TooManyTaskCreations` en **firing**.
3. Alertmanager → http://127.0.0.1:9093 muestra la misma alerta. No manda mail: el receptor está vacío a propósito.

---

## 8. Disparar la alerta de prioridad alta

El Service tiene que apuntar a GREEN:

```bash
kubectl --context=minikube patch svc todo-service -p '{"spec":{"selector":{"app":"todo-app","version":"green"}}}'
```

Reiniciar el port-forward de la app y recargar http://127.0.0.1:5000. Tiene que decir **GREEN v2**.

Crear 6 tareas con prioridad alta:

```powershell
1..6 | ForEach-Object { curl.exe -s -X POST -d "title=urgente-$_&priority=alta" http://127.0.0.1:5000/add }
```

A los ~30 segundos, `TooManyHighPriorityCreations` pasa a firing.

Volver a BLUE:

```bash
kubectl --context=minikube patch svc todo-service -p '{"spec":{"selector":{"app":"todo-app","version":"blue"}}}'
```

Y otra vez: cortar y relanzar el port-forward de `:5000`.

---

## 9. Cambiar X e Y (umbral y ventana)

Se edita el ConfigMap dentro de:

```text
k8s/monitoring/prometheus.yaml
```

- **X** es el número: `> 10`
- **Y** es la ventana: `[5m]`

Ejemplo, más de 20 creaciones en 2 minutos:

```yaml
expr: sum(increase(todo_operations_total{operation="create"}[2m])) > 20
```

Aplicar y reiniciar Prometheus:

```bash
kubectl --context=minikube apply -f k8s/monitoring/prometheus.yaml
kubectl --context=minikube rollout restart deployment/prometheus
```

---

## 10. Comandos útiles

```bash
kubectl --context=minikube get pods,svc
kubectl --context=minikube logs deploy/todo-monitor
kubectl --context=minikube describe svc todo-service
```

Si una URL deja de responder, el port-forward se cayó. Volver a ejecutar el comando de la sección 4.

Para apagar el cluster:

```bash
minikube stop
```
