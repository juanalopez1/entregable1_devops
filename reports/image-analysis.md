# Análisis de las imágenes Docker

El proyecto tiene **dos componentes**, cada uno con su propio Dockerfile:

| Componente | Tecnología | Dockerfile | Imagen final |
|---|---|---|---|
| **todo-app** | Python 3 + Flask (aplicación web de tareas) | `Dockerfile` | `todo-app:1.0.2` |
| **todo-monitor** | Java 21 + Spring Boot (cuenta las operaciones y las expone a Prometheus) | `monitor/Dockerfile` | `todo-monitor:1.0.2` |

Herramientas utilizadas:
- **Snyk Container**: detección de vulnerabilidades (sistema operativo y librerías de la aplicación).
- **Dive v0.13.1**: tamaño de la imagen, composición de las capas y espacio desperdiciado.

## Comandos utilizados

```powershell
# Construcción
docker build -t todo-app:1.0.2 .
docker build -t todo-monitor:1.0.2 ./monitor

# Verificación de usuario no root
docker run --rm todo-app:1.0.2 whoami                   # appuser
docker run --rm --entrypoint id todo-monitor:1.0.2      # uid=10001(appuser) gid=10001(appuser)

# Análisis de capas con Dive (corre como contenedor, no requiere instalación)
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive:v0.13.1 <imagen>

# Escaneo de vulnerabilidades con Snyk
[Console]::OutputEncoding = [Text.Encoding]::UTF8
snyk container test <imagen> --file=<Dockerfile> | Out-File -Encoding utf8 reports/<reporte>.txt
```

> **Nota:** con Dive v0.12.0 se obtuvo el error `could not find 'blobs/sha256/...' in parsed layers`, porque esa versión no soporta el formato de imágenes que usa Docker Desktop actualmente. Se resolvió usando la versión v0.13.1.

> **Nota sobre los tamaños:** `docker image ls` informa tamaños mayores que Dive (por ejemplo, 192 MB contra 128 MB) porque Docker Desktop, con el almacenamiento containerd, también cuenta los datos comprimidos de cada capa. En este reporte se usa el tamaño de Dive, que es el contenido real del sistema de archivos.

## Requisitos cumplidos por ambos Dockerfiles

| Requisito | todo-app | todo-monitor |
|---|---|---|
| Versión específica (no `latest`) | `python:3.15.2-slim-bookworm` | `maven:3.9.9-eclipse-temurin-21` (build) y `eclipse-temurin:21.0.13_9-jre-alpine-3.23` (runtime) |
| Usuario no root | `appuser` (UID/GID 10001) | `appuser` (UID/GID 10001) |
| Multi-stage build | `builder` (pip) → runtime | `build` (Maven + JDK) → runtime (solo JRE) |
| Tag versionado de la imagen propia | `1.0.0` → `1.0.2` | `1.0.0` → `1.0.2` |

---

# 1. todo-app (Flask)

## 1.1 Tamaño y capas (Dive)

| Métrica | 1.0.0 (`python:3.12.7`) | 1.0.1 (`python:3.15.2`) |
|---|---|---|
| Tamaño total | 128 MB | 130 MB |
| Cantidad de capas | 9 | 9 |
| Efficiency score | 97 % | 97 % |
| Wasted space | 4.8 MB | 4.8 MB |

Capturas: `reports/dive-1.0.0.png` y `reports/dive-1.0.1.png`.

Las capas de la versión 1.0.1 son:

| # | Tamaño | Instrucción | Origen |
|---|---|---|---|
| 1 | 75 MB | Sistema base Debian 12 (bookworm) | Imagen base |
| 2 | 8.5 MB | `apt-get install` de dependencias del sistema | Imagen base |
| 3 | 41 MB | Instalación de Python 3.15.2 | Imagen base |
| 4 | 0 B | Enlaces simbólicos (`python3`, `pip3`, etc.) | Imagen base |
| 5 | 4.4 kB | `useradd --uid 10001 ... appuser` | Nuestro Dockerfile |
| 6 | 0 B | `WORKDIR /app` | Nuestro Dockerfile |
| 7 | 5.3 MB | `COPY --from=builder /install /usr/local` (Flask y dependencias) | Nuestro Dockerfile |
| 8 | 1.6 kB | `COPY app.py` | Nuestro Dockerfile |
| 9 | 9.5 kB | `COPY templates` | Nuestro Dockerfile |

- Unos **124 MB (96 %)** corresponden a la imagen base y unos **5 MB (4 %)** a lo que agrega nuestro Dockerfile.
- El espacio desperdiciado (4.8 MB) son archivos de la imagen base que se modifican en más de una capa: `/var/cache/debconf/templates.dat` (2.3 MB), `templates.dat-old` (1.6 MB) y `/var/lib/dpkg/status` (241 kB). Las capas de nuestro Dockerfile no tienen desperdicio.
- La versión **1.0.2** agrega la protección CSRF (`Flask-WTF`), el cliente del monitor (`monitor_client.py`) y un `apt-get upgrade` en la etapa final. Según `docker image ls`, pasa de 194 MB a 196 MB: unos 2 MB más, por la nueva dependencia y el código agregado.

## 1.2 Vulnerabilidades (Snyk)

| Severidad | 1.0.0 (`python:3.12.7`) | 1.0.1 (`python:3.15.2`) | 1.0.2 (+ `apt-get upgrade`) |
|---|---|---|---|
| Critical | 7 | **1** | 1 |
| High | 37 | **7** | 7 |
| Medium | 35 | 9 | 9 |
| Low | 188 | 110 | 110 |
| **Total** | **267** | **127** | **127** |

Reportes: `snyk-image-report.txt` (1.0.0), `snyk-image-report-after.txt` (1.0.1) y `snyk-image-report-1.0.2.txt` (1.0.2).

- **Las vulnerabilidades provienen todas de paquetes del sistema de la imagen base**. Snyk no encontró vulnerabilidades en el código de la aplicación ni en Flask.
- **Corrección aplicada:** se actualizó la imagen base de `python:3.12.7-slim-bookworm` (publicada hace unos dos años) a `python:3.15.2-slim-bookworm`, siguiendo la recomendación de Snyk. Las vulnerabilidades bajaron un **52 %** (de 267 a 127): las críticas pasaron de 7 a 1 y las altas de 37 a 7.
- **`apt-get upgrade` (1.0.2):** no cambió el resultado, porque Debian 12 no publicó parches para las vulnerabilidades restantes (ninguna tiene versión corregida, *"Fixed in"*). Se mantiene como medida preventiva: si Debian publica parches, se aplican en el próximo build. Como contrapartida, el build deja de ser 100 % reproducible, porque los paquetes pueden variar entre un build y otro.

### Críticas y altas restantes (justificación)

| Severidad | Paquete | Cantidad |
|---|---|---|
| Critical | `zlib/zlib1g` (Integer Overflow, SNYK-DEBIAN12-ZLIB-6008963) | 1 |
| High | `zlib/zlib1g` | 2 |
| High | `sqlite3/libsqlite3-0` | 3 |
| High | `pam/libpam0g` | 1 |
| High | `util-linux/libblkid1` | 1 |

- Son paquetes de Debian 12 **sin parche disponible**, por lo que no se pueden resolver actualizando paquetes dentro de bookworm.
- La aplicación no usa directamente estas librerías: no comprime archivos, no usa SQLite (los datos están en memoria) y no autentica usuarios del sistema (PAM). Además, el contenedor corre como usuario no root, lo que limita el impacto de una posible explotación.
- **Se acepta el riesgo residual.** Como mejora futura, se propone migrar a Debian 13 (trixie): Snyk informa que `python:3.16-rc-slim-trixie` tiene 0 críticas y 2 altas. Hoy no se adopta porque Python 3.16 es una versión *release candidate*, no estable.

---

# 2. todo-monitor (Spring Boot)

## 2.1 Tamaño y capas (Dive)

| Métrica | 1.0.0 (Ubuntu + JRE 21.0.5) | 1.0.2 (Alpine + JRE 21.0.13) |
|---|---|---|
| Tamaño total | 314 MB | **236 MB** (−25 %) |
| Cantidad de capas | 8 | 8 |
| Efficiency score | 99 % | 99 % |
| Wasted space | 2.1 MB | **560 kB** |

Capturas: `reports/dive-monitor-1.0.0.png` y `reports/dive-monitor-1.0.2.png`.

Las capas de la versión 1.0.2 son:

| # | Tamaño | Instrucción | Origen |
|---|---|---|---|
| 1 | 8.4 MB | Sistema base Alpine 3.23 | Imagen base |
| 2 | 35 MB | `apk add` (fuentes, certificados, utilidades) | Imagen base |
| 3 | 165 MB | Instalación del JRE de Java 21.0.13 | Imagen base |
| 4 | 0 B | Verificación de la instalación de Java | Imagen base |
| 5 | 6 kB | `entrypoint.sh` (certificados) | Imagen base |
| 6 | 3.1 kB | `addgroup` / `adduser` (usuario 10001) | Nuestro Dockerfile |
| 7 | 0 B | `WORKDIR /app` | Nuestro Dockerfile |
| 8 | 28 MB | `COPY monitor.jar` | Nuestro Dockerfile |

- **El JRE ocupa el 70 % de la imagen** (165 MB). El `.jar` de la aplicación son 28 MB (12 %).
- Al pasar de Ubuntu a Alpine, la base del sistema bajó de **122 MB** (78 MB del sistema más 44 MB de paquetes) a **43 MB** (8.4 MB más 35 MB).
- **El multi-stage es clave en este componente:** la etapa de build usa Maven y el JDK completo (unos 500 MB, con compilador y caché de dependencias). Nada de eso llega a la imagen final, que solo tiene el JRE y el `.jar`.
- El espacio desperdiciado (560 kB) son archivos de la imagen base (certificados, base de datos de `apk`). Nuestras capas no tienen desperdicio.

## 2.2 Vulnerabilidades (Snyk)

Snyk analiza dos niveles por separado: el **sistema operativo** de la imagen y las **librerías Java** dentro del `.jar`.

| | 1.0.0 | 1.0.1 | 1.0.2 |
|---|---|---|---|
| Imagen base | `temurin:21.0.5_11-jre` (Ubuntu) | `temurin:21.0.13_9-jre-alpine-3.23` | ídem |
| Spring Boot | 3.4.5 | 3.5.15 | 3.5.15 + parches |
| **Sistema operativo + JRE** | **319** (3 C, 12 H, 230 M, 74 L) | **1** (1 L) | **1** (1 L) |
| **Librerías Java (`.jar`)** | **128** (15 C, 47 H, 56 M, 10 L) | **60** (7 C, 21 H, 29 M, 3 L) | **17** (1 C, 8 H, 6 M, 2 L) |
| **Total** | **447** | **61** | **18** |

*(C = Critical, H = High, M = Medium, L = Low)*

Reportes: `snyk-monitor-image-report.txt` (1.0.0) y `snyk-monitor-image-report-after.txt` (1.0.2).

**Correcciones aplicadas (de 447 a 18 vulnerabilidades, −96 %):**

1. **Imagen base (1.0.1):** se reemplazó `eclipse-temurin:21.0.5_11-jre` (Ubuntu 24.04) por `eclipse-temurin:21.0.13_9-jre-alpine-3.23`, la recomendada por Snyk.
   - Las 3 críticas eran del propio JRE 21.0.5, corregidas en 21.0.7 y 21.0.8.
   - Las altas venían de paquetes de Ubuntu (`openssl`, `gnupg`, `brotli`, `apt`). Alpine incluye muchos menos paquetes.
   - Resultado: de 319 a **1 baja**, y Snyk indica que es *"the most secure version of the selected base image"*.
2. **Spring Boot 3.4.5 → 3.5.15 (1.0.1):** actualiza en bloque Tomcat, Jackson, Spring Framework, Micrometer y Logback. De 128 a 60.
3. **Versiones forzadas en el `pom.xml` (1.0.2):** Spring Boot permite fijar versiones más nuevas de las librerías que administra, sin cambiar la versión de Spring Boot. Se forzaron `tomcat.version` 10.1.61, `jackson-bom.version` 2.21.8, `logback.version` 1.5.36, `log4j2.version` 2.25.5 y `hibernate-validator.version` 8.0.6.Final. De 60 a 17; las críticas bajaron de 7 a 1.

### Vulnerabilidades restantes (justificación)

| Severidad | Librería | Cantidad | Se corrige en | Motivo para no actualizar |
|---|---|---|---|---|
| Critical | `spring-webmvc` 6.2.19 | 1 | 7.0.9 | Requiere Spring Boot 4 (cambio de versión mayor) |
| High | `spring-web`, `spring-beans`, `spring-expression` 6.2.19 | 6 | 7.0.9 | Ídem |
| High | `micrometer-core` 1.15.12 | 2 | 1.16.7 | Spring Boot 3.5 no soporta oficialmente Micrometer 1.16 |
| Medium / Low | `spring-web`, `spring-webmvc` | 5 | 7.0.9 | Requiere Spring Boot 4 |
| Medium | `logback-classic` 1.5.36 | 2 | 1.6.5 | Logback 1.6 no está soportado por Spring Boot 3.5 |
| Low | `jakarta.validation-api` 3.0.2 | 1 | 4.0.0-M1 | Solo existe en una versión *milestone* (no estable) |

- Las restantes **solo se corrigen migrando a Spring Boot 4 / Spring Framework 7**, que es un cambio de versión mayor con cambios incompatibles. Se deja como mejora futura.
- **Mitigaciones:**
  - El monitor **no está expuesto fuera del cluster**: su Service es `ClusterIP` y no tiene Ingress. Solo recibe peticiones de la aplicación Flask y de Prometheus.
  - Expone un único endpoint propio (`POST /api/operations`), con validación de los datos de entrada, y el endpoint de métricas de Actuator.
  - Corre como usuario no root (UID 10001).
- **Se acepta el riesgo residual** con estas mitigaciones.

---

# 3. Observaciones de optimización

**Aplicadas:**
- **Multi-stage builds** en ambos componentes. Las herramientas de build (pip y su caché; Maven, el JDK y las dependencias descargadas) no llegan a la imagen final.
- **Imágenes base mínimas:** `slim` en Flask (la imagen completa `python` pesa alrededor de 1 GB) y `alpine` con JRE en lugar de JDK en el monitor.
- **Orden de capas para aprovechar la caché:** primero se copian las dependencias (`requirements.txt` y `pom.xml`) y se instalan; después, el código. Si solo cambia el código, Docker reutiliza la capa de dependencias.
- **Copia selectiva:** solo se copian los archivos necesarios para ejecutar (no `COPY . .`), y `.dockerignore` excluye manifiestos, reportes, `.git`, etc.
- **Usuario no root** con UID/GID numérico (10001), necesario para que Kubernetes y Kyverno puedan verificar `runAsNonRoot`.
- **`MaxRAMPercentage=75`** en la JVM: Java ajusta su memoria al límite del contenedor y evita que Kubernetes lo termine por exceso de memoria (OOMKilled).

**Posibles mejoras futuras:**
1. **Flask:** migrar a Debian 13 (trixie) cuando haya una versión estable de Python sobre esa base, para eliminar la vulnerabilidad crítica de `zlib`.
2. **Monitor:** migrar a Spring Boot 4 para eliminar las vulnerabilidades de Spring Framework.
3. **Monitor:** generar un JRE reducido con `jlink`, que incluya solo los módulos de Java que usa la aplicación. Podría reducir los 165 MB del JRE a unos 50–70 MB.
4. **Flask:** usar una imagen *distroless* (sin shell ni gestor de paquetes) para reducir la superficie de ataque, a costa de dificultar la depuración.
5. **Escaneo automático en el pipeline (Jenkins):** que el build se detenga ante vulnerabilidades críticas nuevas.
