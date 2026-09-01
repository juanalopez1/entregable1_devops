# agarrar imagen de python
FROM python:3.12-slim

# crea/usa /app dentro del contenedor.
WORKDIR /app

# copia las dependencias e instala Flask.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# copia toda nuestra aplicación al contenedor.
COPY . .

# indica que Flask usa el puerto 5000.
EXPOSE 5000

# cuando arranca el contenedor ejecuta nuestra aplicación.
CMD ["python", "app.py"]