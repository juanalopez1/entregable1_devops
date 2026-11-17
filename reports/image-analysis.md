# Análisis de la imagen Docker

Imagen analizada: `todo-app:1.0.0`
Imagen base: `python:3.12.7-slim-bookworm`
Herramientas: **Dive v0.13.1** (tamaño y capas) y **Snyk Container** (vulnerabilidades).

## Comandos utilizados

```powershell
# Construcción de la imagen
docker build -t todo-app:1.0.0 .

# Análisis de capas con Dive (corre como contenedor, no requiere instalación)
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive:v0.13.1 todo-app:1.0.0

# Cantidad de capas
docker inspect -f "{{len .RootFS.Layers}}" todo-app:1.0.0

# Escaneo de vulnerabilidades con Snyk
snyk container test todo-app:1.0.0 --file=Dockerfile | Out-File -Encoding utf8 reports/snyk-image-report.txt
```

> Nota: con Dive v0.12.0 se obtuvo el error `could not find 'blobs/sha256/...' in parsed layers`,
> porque esa versión no soporta el formato de imágenes que usa Docker Desktop actualmente.
> Se resolvió usando la versión v0.13.1.

## 1. Tamaño total

| Fuente | Tamaño |
|---|---|
| Dive (contenido real del sistema de archivos) | **128 MB** |
| `docker image ls` (Docker Desktop) | 192 MB |

La diferencia se debe a que Docker Desktop, con el almacenamiento containerd, también cuenta los datos comprimidos que guarda de cada capa. El tamaño real de la imagen es el que informa Dive.

## 2. Cantidad de capas

La imagen tiene **9 capas**. Instrucciones como `ENV`, `USER`, `EXPOSE` y `CMD` solo agregan metadatos y no generan capas.

| # | Tamaño | Instrucción | Origen |
|---|---|---|---|
| 1 | 75 MB | Sistema base Debian 12 (bookworm) | Imagen base |
| 2 | 8.5 MB | `apt-get install` de dependencias del sistema | Imagen base |
| 3 | 40 MB | Instalación de Python 3.12.7 | Imagen base |
| 4 | 0 B | Enlaces simbólicos (`python3`, `pip3`, etc.) | Imagen base |
| 5 | 4.4 kB | `useradd --uid 10001 ... appuser` | Nuestro Dockerfile |
| 6 | 0 B | `WORKDIR /app` | Nuestro Dockerfile |
| 7 | 4.8 MB | `COPY --from=builder /install /usr/local` (Flask y dependencias) | Nuestro Dockerfile |
| 8 | 1.6 kB | `COPY app.py` | Nuestro Dockerfile |
| 9 | 9.5 kB | `COPY templates` | Nuestro Dockerfile |

Unos **123 MB (96 %)** corresponden a la imagen base y unos **4.8 MB (4 %)** a lo que agrega nuestro Dockerfile.

## 3. Eficiencia (Dive)

| Métrica | Valor |
|---|---|
| Image efficiency score | **97 %** |
| Potential wasted space | **4.8 MB** |

El espacio desperdiciado son archivos que una capa crea y otra posterior modifica, por lo que quedan duplicados:

| Repeticiones | Espacio | Archivo |
|---|---|---|
| 3 | 2.3 MB | `/var/cache/debconf/templates.dat` |
| 2 | 1.6 MB | `/var/cache/debconf/templates.dat-old` |
| 3 | 247 kB | `/var/lib/dpkg/status` |

Todos estos archivos pertenecen a las capas de la **imagen base** (instalación de paquetes con apt). Las capas generadas por nuestro Dockerfile no tienen desperdicio.

## 4. Vulnerabilidades (Snyk)

Resultado completo en `reports/snyk-image-report.txt`.

| Severidad | Cantidad |
|---|---|
| Critical | 7 |
| High | 37 |
| Medium | 35 |
| Low | 188 |
| **Total** | **267** |

- Las 267 vulnerabilidades provienen de **paquetes del sistema de la imagen base**. Las críticas están en `perl-base`, `gnutls`, `zlib` y `openssl`.
- Snyk no encontró vulnerabilidades en el código de la aplicación ni en Flask.
- La causa es que `python:3.12.7-slim-bookworm` fue publicada hace unos dos años y no incluye los parches de seguridad posteriores.

## 5. Observaciones y optimizaciones

**Aplicadas en el Dockerfile:**
- **Multi-stage build:** las dependencias se instalan en una etapa `builder` y solo se copia el resultado (4.8 MB). La caché de pip y los archivos temporales no llegan a la imagen final.
- **Imagen base `slim`:** Debian sin herramientas innecesarias. La imagen completa `python:3.12` pesa unos 1 GB.
- **Versión fija** de la imagen base y tag versionado de la imagen propia (`1.0.0`, sin `latest`).
- **Usuario no root** (`appuser`, UID 10001).
- **`.dockerignore`** para no copiar al contexto de build archivos que la app no necesita (manifiestos, reportes, `.git`, etc.).
- **Orden de capas:** `requirements.txt` se copia e instala antes que el código. Si solo cambia el código, Docker reutiliza la capa de dependencias desde la caché.

**Optimizaciones posibles:**
1. **Actualizar la imagen base** a la recomendada por Snyk (`python:3.15.2-slim-bookworm`), que reduce las vulnerabilidades de 267 a 127 (de 7 a 1 críticas). Es la corrección prioritaria.
2. **Imagen base alpine**, más chica (unos 50 MB). Snyk informa 0 vulnerabilidades para `python:3.16-rc-alpine3.24`, pero es una versión *release candidate*. Además, alpine usa `musl` en lugar de `glibc`, lo que puede traer incompatibilidades con algunas librerías.
3. **Imagen distroless** (sin shell ni gestor de paquetes): reduce mucho la superficie de ataque, a costa de dificultar la depuración.
4. El desperdicio de 4.8 MB no se puede eliminar sin cambiar la imagen base, porque se genera en sus capas.

## 6. Corrección aplicada: actualización de la imagen base

Siguiendo la recomendación de Snyk, se cambiaron las dos instrucciones `FROM` del Dockerfile:

```dockerfile
FROM python:3.15.2-slim-bookworm AS builder
...
FROM python:3.15.2-slim-bookworm
```

Y se construyó una nueva versión de la imagen:

```powershell
docker build -t todo-app:1.0.1 .
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive:v0.13.1 todo-app:1.0.1
snyk container test todo-app:1.0.1 --file=Dockerfile | Out-File -Encoding utf8 reports/snyk-image-report-after.txt
```

### Comparación

| Métrica | 1.0.0 (`python:3.12.7`) | 1.0.1 (`python:3.15.2`) |
|---|---|---|
| Tamaño total (Dive) | 128 MB | 130 MB |
| Cantidad de capas | 9 | 9 |
| Capa de Python (imagen base) | 40 MB | 41 MB |
| Capa de dependencias (`/install`) | 4.8 MB | 5.3 MB |
| Efficiency score | 97 % | 97 % |
| Wasted space | 4.8 MB | 4.8 MB |
| Vulnerabilidades críticas (Snyk) | 7 | **1** |
| Vulnerabilidades altas (Snyk) | 37 | **7** |
| Vulnerabilidades medias (Snyk) | 35 | 9 |
| Vulnerabilidades bajas (Snyk) | 188 | 110 |
| **Vulnerabilidades totales (Snyk)** | **267** | **127** |

Resultado completo en `reports/snyk-image-report-after.txt`.

**Conclusión:** la actualización mantiene prácticamente el mismo tamaño (+2 MB, por la versión más nueva de Python y de los wheels de las dependencias) y la misma estructura de capas, y reduce las vulnerabilidades un **52 %** (de 267 a 127), con las críticas pasando de 7 a 1 y las altas de 37 a 7. El desperdicio de 4.8 MB se mantiene porque sigue siendo la misma base Debian 12.

### Vulnerabilidades críticas y altas restantes (justificación)

| Severidad | Paquete | Cantidad |
|---|---|---|
| Critical | `zlib/zlib1g` (Integer Overflow, SNYK-DEBIAN12-ZLIB-6008963) | 1 |
| High | `zlib/zlib1g` | 2 |
| High | `sqlite3/libsqlite3-0` | 3 |
| High | `pam/libpam0g` | 1 |
| High | `util-linux/libblkid1` | 1 |

- Todas son **paquetes del sistema Debian 12** incluidos en la imagen base; ninguna está en el código de la aplicación ni en Flask.
- Snyk **no informa versión corregida** ("Fixed in") para la vulnerabilidad crítica de zlib: Debian 12 no publicó un parche, así que no se puede resolver actualizando paquetes dentro de bookworm.
- La aplicación no usa directamente estas librerías: no comprime archivos, no usa SQLite (los datos están en memoria) y no hace autenticación de usuarios del sistema (PAM). Además, el contenedor corre como usuario no root, lo que limita el impacto de una posible explotación.
- **Se acepta el riesgo residual** y se deja como mejora futura migrar a una base más nueva. Las alternativas que propone Snyk son `python:3.16-rc-slim-trixie` (Debian 13: 0 críticas, 2 altas) y `python:3.16-rc-alpine3.24` (0 vulnerabilidades). Hoy no se adoptan porque son versiones *release candidate* de Python, no estables. Cuando salga la versión estable de Python 3.16, convendría migrar.
