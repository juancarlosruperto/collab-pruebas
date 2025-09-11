#!/bin/bash
set -e

echo "🚀 Iniciando aplicación en contenedor..."

# Ir al directorio donde está el código (ya copiado en /app por el Dockerfile)
cd /app

# Levantar FastAPI con uvicorn en el puerto 8020
exec uvicorn app:app --host 0.0.0.0 --port 8020