#!/bin/bash
set -e

echo "🚀 Iniciando aplicación en contenedor..."

# Movernos al directorio base
cd /workspace

# Verificar si existe app.py
if [ ! -f "app.py" ]; then
  echo "❌ Error: no se encuentra app.py en /workspace"
  exit 1
fi

# Iniciar la aplicación en el puerto 8020
exec python app.py --port 8020
