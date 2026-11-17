# ---------- Etapa 1: builder ----------
# Instala las dependencias en una carpeta aparte (/install)
FROM python:3.15.2-slim-bookworm AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- Etapa 2: runtime ----------
# Imagen final: solo Python + dependencias ya instaladas + nuestro código
FROM python:3.15.2-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Usuario sin privilegios, con UID numérico
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

# Copiamos solo lo instalado en la etapa 1 (sin caché ni restos de pip)
COPY --from=builder /install /usr/local

# Copiamos solo lo que la app necesita para correr
COPY --chown=appuser:appuser app.py .
COPY --chown=appuser:appuser templates ./templates

USER 10001

EXPOSE 5000

CMD ["python", "app.py"]