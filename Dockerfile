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
# Nota: start.sh usa 8020
EXPOSE 8020

# Comando para iniciar la app
CMD ["/app/start.sh"]

