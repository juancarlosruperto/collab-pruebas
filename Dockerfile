FROM python:3.9-slim

# Crear directorio de trabajo
WORKDIR /app

# Copiar dependencias e instalarlas
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar todo el código
COPY . .

# Dar permisos al start.sh
RUN chmod +x /app/start.sh

# Exponer el puerto 8020
EXPOSE 8020

# Usar start.sh como punto de entrada
CMD ["/app/start.sh"]