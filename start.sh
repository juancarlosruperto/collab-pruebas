#!/bin/bash
set -e

echo "🚀 Iniciando aplicación en contenedor..."

cd /app

if [ ! -f "app.py" ]; then
  echo "❌ Error: no se encuentra app.py en /app"
  ls -la
  exit 1
fi

exec uvicorn app:app --host 0.0.0.0 --port 8020

