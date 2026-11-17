# agarrar imagen de python
FROM python:3.12-slim

# Aplica las actualizaciones de seguridad disponibles en Debian al construir la imagen.
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# crea/usa /app dentro del contenedor.
WORKDIR /app

# copia las dependencias e instala Flask.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser

# copia toda nuestra aplicación al contenedor.
COPY . .

# indica que Flask usa el puerto 5000.
EXPOSE 5000

USER 10001:10001

# cuando arranca el contenedor ejecuta nuestra aplicación.
CMD ["python", "app.py"]
