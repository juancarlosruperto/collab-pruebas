#!/usr/bin/env bash
set -euo pipefail
unset PYTORCH_CUDA_ALLOC_CONF || true

# --- Paths base ---
BASE_DIR="/workspace"
APP_DIR="$BASE_DIR/app"
LOG_DIR="$BASE_DIR/logs"

# --- Fix permissions if running as non-root and with mounted volume ---
chown -R $(id -u):$(id -g) "$BASE_DIR/.cache" || true

# --- Caches (persistentes) ---
export HF_HOME="$BASE_DIR/.cache/huggingface"
export PIP_CACHE_DIR="$BASE_DIR/.cache/pip"

# --- Config / Secrets (EXPORTAR EXPLÍCITAMENTE) ---
export API_TOKEN="${API_TOKEN:-R4d104ct1v0!}"
export HF_TOKEN="${HF_TOKEN:-}"
# MANTENER Mixtral-8x7B pero con optimizaciones
export HC_MODEL_ID="${HC_MODEL_ID:-mistralai/Mixtral-8x7B-Instruct-v0.1}"
export SEC_MODEL_PATH="${SEC_MODEL_PATH:-$BASE_DIR/models/baron.gguf}"
export ETHICS_MODEL_ID="${ETHICS_MODEL_ID:-mistralai/Mixtral-8x7B}"

# --- Optimizations for large models ---
echo "🚀 Configuring for Mixtral-8x7B (Large Model Mode)..."
export PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512,expandable_segments:True"
export CUDA_LAUNCH_BLOCKING=0
export TOKENIZERS_PARALLELISM=false
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4

# Force 4-bit quantization for Mixtral
export LOAD_IN_4BIT=true
export USE_FLASH_ATTENTION=true

# Timeouts largos para Mixtral
export UVICORN_TIMEOUT_KEEP_ALIVE="${UVICORN_TIMEOUT_KEEP_ALIVE:-300}"  # 5 min
export MODEL_LOAD_TIMEOUT="${MODEL_LOAD_TIMEOUT:-600}"  # 10 min para carga inicial
export GENERATION_TIMEOUT="${GENERATION_TIMEOUT:-120}"  # 2 min para generación
export DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-1800}"  # 30 min para descarga

# Memory settings
export HF_HUB_ENABLE_HF_TRANSFER=1  # Descarga más rápida
export HF_HUB_DISABLE_SYMLINKS=1

echo "==================================="
echo "🧠 AITOPS - Mixtral-8x7B Mode"
echo "==================================="
echo "  Model: $HC_MODEL_ID"
echo "  4-bit Quantization: ${LOAD_IN_4BIT}"
echo "  Flash Attention: ${USE_FLASH_ATTENTION}"
echo "  Model Load Timeout: ${MODEL_LOAD_TIMEOUT}s"
echo "  Generation Timeout: ${GENERATION_TIMEOUT}s"
echo "  HF Token: ${HF_TOKEN:+SET}${HF_TOKEN:-EMPTY}"
echo "==================================="

# --- Estructura necesaria ---
mkdir -p "$LOG_DIR" "$HF_HOME" "$PIP_CACHE_DIR" "$BASE_DIR/models"

# --- Guard hf_transfer (usando python global) ---
if [[ "${HF_HUB_ENABLE_HF_TRANSFER:-0}" == "1" ]]; then
  if ! python -c "import hf_transfer" 2>/dev/null; then
    echo "WARN: HF_HUB_ENABLE_HF_TRANSFER=1 pero 'hf_transfer' no está instalado; desactivando."
    export HF_HUB_ENABLE_HF_TRANSFER=0
  fi
fi

# --- Validar archivos clave ---
required_files=(
  "$APP_DIR/json_utils.py"
  "$APP_DIR/logging_config.py"
  "$APP_DIR/agents/hc_analyst.py"
  "$APP_DIR/app_memory.py"
)
for f in "${required_files[@]}"; do
  [[ -f "$f" ]] || { echo "ERROR: falta $f"; exit 1; }
done
echo "OK: archivos presentes"

# --- Verificar FastAPI (usando python global) ---
echo "Verificando dependencias..."
if ! python -c "import fastapi; print('fastapi OK')" 2>/dev/null; then
  echo "FastAPI no encontrado, instalando dependencias..."
  python -m pip install -U pip
  python -m pip install -r "$BASE_DIR/requirements.txt"
else
  echo "Dependencias OK"
fi

# --- Smoke test rápido ---
# --- Smoke test rápido ---
echo "Ejecutando smoke tests..."
python -c "
import os
print('=== Verificando variables en Python ===')
print(f'HC_MODEL_ID: {os.getenv(\"HC_MODEL_ID\")}')
print(f'HF_TOKEN: {\"SET\" if os.getenv(\"HF_TOKEN\") else \"EMPTY\"}')

from app.logging_config import setup_logging
setup_logging()
print('logging_config OK')

from app.agents.hc_analyst import HCAnalyst
from app.json_utils import parse_json_strict
print('imports OK')
"

# --- Pre-download check para Mixtral ---
echo "📥 Checking Mixtral-8x7B cache..."
python -c "
import os
from pathlib import Path

cache_dir = Path(os.getenv('HF_HOME', '/workspace/.cache/huggingface'))
model_id = os.getenv('HC_MODEL_ID', '')
model_cache = cache_dir / 'hub' / f"models--{model_id.replace('/', '--')}"

if model_cache.exists():
    total_size = sum(f.stat().st_size for f in model_cache.rglob('*') if f.is_file())
    size_gb = total_size / (1024**3)
    print(f'✅ Model cached: {size_gb:.1f}GB')
else:
    print('⚠️  Model not cached. First run will download ~50GB')
    print('   This may take 15-30 minutes depending on connection')
    print('   The download will resume if interrupted')
"

# --- GPU check con validación de VRAM ---
echo "🎮 Validating GPU for Mixtral-8x7B..."
python -c "
import torch
import sys

if not torch.cuda.is_available():
    print('❌ NO GPU DETECTED - Mixtral-8x7B requires GPU!')
    sys.exit(1)

for i in range(torch.cuda.device_count()):
    props = torch.cuda.get_device_properties(i)
    vram_gb = props.total_memory / (1024**3)
    print(f'  GPU {i}: {props.name}')
    print(f'    VRAM: {vram_gb:.1f}GB')
    if vram_gb < 24:
        print(f'    ⚠️  WARNING: Less than 24GB VRAM. Will use 4-bit quantization')
    else:
        print(f'    ✅ Sufficient VRAM for Mixtral-8x7B')

# Check RAM
import psutil
ram_gb = psutil.virtual_memory().total / (1024**3)
ram_available_gb = psutil.virtual_memory().available / (1024**3)
print(f'  System RAM: {ram_available_gb:.1f}GB available / {ram_gb:.1f}GB total')
if ram_available_gb < 16:
    print('    ⚠️  WARNING: Low RAM. May cause issues during loading')
"

# --- Pre-load opcional (descomentar si quieres pre-cargar) ---
# echo "🔄 Pre-loading Mixtral-8x7B into memory..."
# python -c "
# from app.agents.hc_analyst import HCAnalyst
# print('Pre-loading model...')
# agent = HCAnalyst()
# print('Model pre-loaded successfully')
# " || echo "⚠️  Pre-load failed, will load on first request"

# --- Monitoreo de recursos (background opcional) ---
(while true; do
    nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu \
        --format=csv,noheader,nounits > /workspace/logs/gpu_usage.log
    sleep 30
done) &

# --- Uvicorn optimizado para Mixtral ---
echo "🚀 Starting FastAPI (Mixtral-8x7B optimized)..."
exec uvicorn app.app_memory:app \
    --host 0.0.0.0 \
    --port 8020 \
    --log-level info \
    --access-log \
    --timeout-keep-alive $UVICORN_TIMEOUT_KEEP_ALIVE \
    --timeout-graceful-shutdown 30 \
    --limit-max-requests 100 \
    --limit-max-request-line 8190 \
    --ws-max-size 16777216
