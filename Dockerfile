# Dockerfile
FROM python:3.9-slim

WORKDIR /app

# Copiar dependencias e instalarlas
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar todo el código
COPY . .

# Copiar el start.sh y darle permisos
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Exponer puerto
EXPOSE 8888  # Nota: start.sh usa 8888

# Comando para iniciar la app
CMD ["/app/start.sh"]

