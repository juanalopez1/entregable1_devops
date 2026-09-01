# Entregable 1 - DevOps

Aplicación simple de gestión de tareas desarrollada en **Python con Flask**.

El objetivo del proyecto es contenerizar la aplicación con Docker, desplegarla en Kubernetes utilizando Minikube y demostrar una estrategia de despliegue **Blue/Green**.

---

## 1. Ejecutar la aplicación localmente

Primero instalamos las dependencias del proyecto:

```bash
pip install -r requirements.txt
```

Luego ejecutamos la aplicación:

```bash
python app.py
```

La aplicación queda disponible en:

http://localhost:5000

---

## 2. Construir la imagen Docker BLUE

Construimos la imagen Docker correspondiente a la primera versión de la aplicación:

```bash
docker build -t todo-app:blue .
```

Podemos verificar que la imagen fue creada correctamente con:

```bash
docker images
```

Debería aparecer una imagen llamada:

```text
todo-app:blue
```

---

## 3. Ejecutar BLUE utilizando Docker

Creamos y ejecutamos un contenedor utilizando la imagen BLUE:

```bash
docker run -p 5000:5000 --name todo-blue todo-app:blue
```

La opción:

```text
-p 5000:5000
```

mapea el puerto `5000` de nuestra computadora al puerto `5000` del contenedor, donde está ejecutándose Flask.

Luego podemos acceder a:

http://localhost:5000

### Detener el contenedor

```bash
docker stop todo-blue
```

### Eliminar el contenedor

```bash
docker rm todo-blue
```

---

# Despliegue en Kubernetes

## 4. Iniciar Minikube

Iniciamos un cluster local de Kubernetes utilizando Minikube:

```bash
minikube start
```

Verificamos que el nodo de Kubernetes esté funcionando:

```bash
kubectl get nodes
```

El nodo `minikube` debería aparecer con estado:

```text
Ready
```

---

## 5. Cargar la imagen BLUE en Minikube

Como la imagen `todo-app:blue` está almacenada localmente y no fue publicada en Docker Hub, debemos cargarla dentro de Minikube para que Kubernetes pueda utilizarla.

```bash
minikube image load todo-app:blue
```

Podemos verificar las imágenes disponibles dentro de Minikube con:

```bash
minikube image ls
```

---

## 6. Desplegar BLUE en Kubernetes

Creamos el Deployment correspondiente a la versión BLUE:

```bash
kubectl apply -f k8s/deployment-blue.yaml
```

Luego creamos el Service:

```bash
kubectl apply -f k8s/service.yaml
```

Podemos verificar el Deployment:

```bash
kubectl get deployments
```

Y los Pods:

```bash
kubectl get pods
```

Deberíamos tener un Pod similar a:

```text
todo-blue-xxxxxxxxxx-xxxxx   1/1   Running
```

También podemos comprobar el Service:

```bash
kubectl get services
```

---

## 7. Acceder a la aplicación desde Kubernetes

Para acceder a la aplicación desplegada en Minikube:

```bash
minikube service todo-service
```

En este punto, el Service de Kubernetes dirige el tráfico hacia la versión:

```text
BLUE v1
```

---

# Versión GREEN

La segunda versión de la aplicación agrega nuevas funcionalidades:

- Prioridades para las tareas: `Baja`, `Media` y `Alta`.
- Filtros de tareas: `Todas`, `Pendientes` y `Completadas`.
- Cambios visuales para identificar fácilmente la versión GREEN.

---

## 8. Construir la imagen GREEN

La versión GREEN utiliza el archivo:

```text
Dockerfile.green
```

Construimos su imagen con:

```bash
docker build -f Dockerfile.green -t todo-app:green .
```

Verificamos las imágenes:

```bash
docker images
```

Ahora deberíamos tener ambas versiones:

```text
todo-app:blue
todo-app:green
```

---

## 9. Cargar GREEN en Minikube

Cargamos también la nueva imagen:

```bash
minikube image load todo-app:green
```

Podemos comprobar que BLUE y GREEN estén disponibles:

```bash
minikube image ls
```

---

## 10. Desplegar GREEN en Kubernetes

Creamos el Deployment GREEN:

```bash
kubectl apply -f k8s/deployment-green.yaml
```

Verificamos los Pods:

```bash
kubectl get pods
```

En este punto deberían estar ejecutándose simultáneamente ambas versiones:

```text
todo-blue-xxxxxxxxxx    1/1   Running
todo-green-xxxxxxxxxx   1/1   Running
```

---

# Estrategia Blue/Green

La estrategia Blue/Green mantiene dos versiones de la aplicación desplegadas al mismo tiempo.

En nuestro caso:

```text
BLUE  -> versión 1
GREEN -> versión 2
```

Ambas versiones están ejecutándose en Kubernetes, pero el `Service` determina cuál de ellas recibe el tráfico de los usuarios.

Inicialmente el Service utiliza el siguiente selector:

```yaml
selector:
  app: todo-app
  version: blue
```

Por lo tanto:

```text
Usuario
   |
   v
todo-service
   |
   v
BLUE v1
```

---

## 11. Cambiar el tráfico de BLUE a GREEN

Para desplegar la nueva versión modificamos el selector del archivo:

```text
k8s/service.yaml
```

Cambiamos:

```yaml
version: blue
```

por:

```yaml
version: green
```

Luego aplicamos nuevamente el Service:

```bash
kubectl apply -f k8s/service.yaml
```

A partir de ese momento el tráfico pasa a GREEN:

```text
Usuario
   |
   v
todo-service
   |
   v
GREEN v2
```

Podemos comprobar el selector actual con:

```bash
kubectl describe service todo-service
```

Debería aparecer:

```text
Selector: app=todo-app,version=green
```

---

## Rollback

Una ventaja de Blue/Green es que la versión anterior continúa ejecutándose.

Si la versión GREEN presenta algún problema, podemos volver rápidamente a BLUE modificando nuevamente el selector:

```yaml
version: blue
```

Y aplicando:

```bash
kubectl apply -f k8s/service.yaml
```

No es necesario reconstruir ni volver a desplegar la versión anterior porque BLUE continúa ejecutándose dentro del cluster.

---

## Almacenamiento

Actualmente las tareas se almacenan en memoria dentro de cada instancia de la aplicación.

Por este motivo, si un Pod es eliminado o reiniciado, las tareas almacenadas en ese Pod se pierden.

Además, BLUE y GREEN mantienen memorias independientes, ya que son Pods distintos.

Esta decisión fue tomada para mantener el alcance del proyecto enfocado principalmente en Docker, Kubernetes y la estrategia Blue/Green.
