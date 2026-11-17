# Entregable 3 - DevSecOps

## Seguridad en el código

Ejecutamos un análisis estático de código utilizando Semgrep levantándolo en docker con el siguiente comando:

```bash
docker run --rm --mount "type=bind,source=$($PWD.Path),target=/src" --workdir /src semgrep/semgrep semgrep scan --config auto . 2>&1 | Tee-Object -FilePath reports/semgrep.txt
```

Con esto la herramienta elige automáticamente que reglas utilizar para el scan y luego guarda el resultado en un txt dentro del directorio reports que utilizaremos para los demás análisis. 

El resultado de la primera ejecución informó 346 reglas ejecutadas sobre 23 archivos y 13 hallazgos clasificados como bloqueantes.

### Correcciones aplicadas

- **Protección CSRF en formularios:** el hallazgo de las plantillas indicaba una regla Django, aunque la aplicación usa Flask. Al revisar el código se confirmó que los formularios POST no tenían tokens CSRF. Se agregó `Flask-WTF`, se habilitó `CSRFProtect` en BLUE y GREEN y se incluyó un campo `csrf_token` en todos los formularios POST. La regla Django se suprimió en esas líneas porque no reconoce el mecanismo Flask-WTF; la protección está implementada en la aplicación.
- **Acciones de GitHub:** `actions/checkout` y `docker/login-action` se fijaron a SHA completos e inmutables para evitar referencias de etiqueta que puedan cambiar.

### Alertas conservadas con justificación

- **`app.run(host="0.0.0.0")`:** se conserva porque Flask debe escuchar en todas las interfaces dentro del contenedor para recibir tráfico desde Docker o Kubernetes. La exposición se controla mediante la publicación de puertos y el Service del clúster. La supresión local de Semgrep incluye esta justificación.
- **`k8s/noncompliant-pod.yaml`:** el manifiesto es deliberadamente inseguro y se usa como prueba negativa para comprobar que Kyverno rechace pods no conformes. Sus alertas de ejecución como root y escalada de privilegios son esperadas; no debe desplegarse como aplicación.
- **`k8s/policies/require-resources.yaml`:** la regla genérica de Kubernetes interpreta el campo `spec` de una `ClusterPolicy` de Kyverno como si fuera el `spec` de un Pod. Es un falso positivo de esquema; el archivo declara una política, no un workload. La supresión queda junto al campo afectado.

## Seguridad en la imágen

Analizamos la imágen de docker con Trivy con los comandos: 

```powershell
docker build -f Dockerfile -t todo-app:devsecops .
docker save -o todo-app-devsecops.tar todo-app:devsecops
docker run --rm --mount "type=bind,source=$($PWD.Path),target=/work" aquasec/trivy:0.76.2 image --input /work/todo-app-devsecops.tar --scanners vuln --severity HIGH,CRITICAL --format table --output /work/reports/trivyreport.txt
```

El primero construye la imagen, el segundo la guarda temporalmente en un archivo para que Trivy pueda leerla y el tercero hace el análisis y escribe el informe. Para esto utilizamos la versión 0.76.2 de la imagen oficial de Trivy. 

La imagen `todo-app:devsecops`, construida desde `Dockerfile`, se identificó como Debian 13.7. El primer análisis encontró 48 vulnerabilidades HIGH y 0 CRITICAL. Los paquetes Python de la imagen no mostraron vulnerabilidades en este reporte inicial. Los 48 resultados son incidencias por paquete y corresponden a 12 CVE distintos.

El reporte inicial mostró que `zlib1g` tenía una versión corregida (`1:1.3.dfsg+really1.3.1-1+deb13u1`), mientras que la imagen contenía `1:1.3.dfsg+really1.3.1-1+b1`. Se actualizó la construcción de los Dockerfiles BLUE y GREEN para ejecutar `apt-get update` y `apt-get upgrade` antes de instalar la aplicación. La reconstrucción actualizó `zlib1g` a la versión corregida.

El nuevo escaneo quedó guardado en `reports/trivyreport.txt`: 47 HIGH, 0 CRITICAL y 11 CVE distintos. La mayoría afecta paquetes del sistema Debian y Trivy no muestra una versión corregida para ellos. `perl-base` (`CVE-2026-9538`) aparece con estado `fix_deferred`. Debian solo publicó una actualización aplicable a `zlib1g` durante esta reconstrucción.

## Seguridad en Kubernetes

Kyverno aplica reglas cuando Kubernetes recibe recursos. Las políticas usan Enforce, por lo que un recurso que no las cumple debe ser rechazado. KubeLinter, en cambio, analiza los manifiestos YAML antes de desplegarlos y recomienda mejoras.

```powershell
kubectl apply -f k8s/policies/
kubectl get cpol
```

Las tres políticas hacen lo siguiente:

disallow-latest-tag: rechaza imágenes con la etiqueta latest.

require-container-resources: exige solicitudes y límites de CPU y memoria para los contenedores.

disallow-root-containers: exige que los contenedores se ejecuten como usuario distinto de root.

Los Deployments BLUE y GREEN cumplen estos controles: usan etiquetas distintas de latest, definen recursos y ejecutan con UID 10001.

Luego ejecutamos:

```powershell
kubectl apply -f k8s/noncompliant-pod.yaml
```

El manifiesto de prueba usa `nginx:latest`, no define CPU/memoria y no configura un usuario sin privilegios. Con Kyverno activo, Kubernetes debe rechazarlo y mostrar una denegación de admisión. El Pod no debería quedar creado.

```powershell
docker run --rm --mount "type=bind,source=$($PWD.Path),target=/src" stackrox/kube-linter:v0.8.3 lint /src/k8s --format plain --output /src/reports/kubelinter.txt
```

El resultado queda en `reports/kubelinter.txt`. En el análisis actual aparecen cinco hallazgos, todos en `noncompliant-pod.yaml`, que es deliberadamente no conforme para la demostración. Los Deployments BLUE y GREEN ya incluyen `readOnlyRootFilesystem: true`.

Al aplicar k8s/noncompliant-pod.yaml, el webhook de Kyverno rechazó el Pod por las tres políticas; luego se confirmó que no fue creado. KubeLinter reportó cinco hallazgos, todos en ese manifiesto de prueba deliberadamente no conforme.

## Seguridad en tiempo de ejecución

Instalamos Falco en el clúster Minikube usando el chart oficial de Helm. Falco incluye reglas preinstaladas y muestra cómo revisar sus pods y logs. Creamos el pod de prueba `falco-shell-test` con una imagen etiquetada, límites y solicitudes de recursos, y ejecución como usuario no root.

Con el comando: 

`kubectl exec -it falco-shell-test -- sh` 

abrimos una shell dentro del pod y ejecutamos algún comando por ejemplo `id`. 

Luego en los logs de Falco podemos ver la alerta **“A shell was spawned in a container with an attached terminal”**, asociada al pod `falco-shell-test`. Esto lo guardamos en el directorio de reports. 

Falco registró correctamente la apertura de la shell. Las políticas Kyverno continúan aplicándose en los demás namespaces; se excluyó `falco` de las políticas de no-root y recursos para permitir el funcionamiento del agente de monitoreo.