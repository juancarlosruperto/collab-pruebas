import os
import re
import json
from typing import Dict, Any
from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import torch
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM

# -----------------------------
# Configuración de FastAPI
# -----------------------------
app = FastAPI(title="AI System Analysis API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------
# Modelo de entrada
# -----------------------------
class PromptRequest(BaseModel):
    prompt: str
    user_id: str = "anonymous"
    model_name: str = "google/flan-t5-large"

# -----------------------------
# Variables globales
# -----------------------------
model = None
tokenizer = None

# -----------------------------
# Función para cargar modelo
# -----------------------------
def load_model(model_name="google/flan-t5-large"):
    global model, tokenizer
    try:
        device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"➡️ Cargando modelo {model_name} en {device}")
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForSeq2SeqLM.from_pretrained(
            model_name,
            device_map="auto" if device == "cuda" else None,
            torch_dtype=torch.float16 if device == "cuda" else torch.float32
        )
        print("✅ Modelo cargado exitosamente")
    except Exception as e:
        print(f"❌ Error cargando modelo: {e}")

# Cargar modelo al inicio
load_model()

# -----------------------------
# Función para extraer métricas
# -----------------------------
def extraer_metricas_del_prompt(prompt: str) -> Dict[str, Any]:
    metricas = {}
    try:
        cpu_match = re.search(r'CPU utilization:\s*([\d.]+)%', prompt, re.IGNORECASE)
        if cpu_match:
            metricas['cpu_utilization_percent'] = float(cpu_match.group(1))

        mem_total_match = re.search(r'Total memory:\s*([\d.]+)\s*MB', prompt, re.IGNORECASE)
        mem_avail_match = re.search(r'Available memory:\s*([\d.]+)\s*MB', prompt, re.IGNORECASE)
        if mem_total_match and mem_avail_match:
            total = float(mem_total_match.group(1))
            available = float(mem_avail_match.group(1))
            metricas['memory_total_mb'] = total
            metricas['memory_available_mb'] = available
            metricas['memory_utilization_percent'] = round((total - available) / total * 100, 2)
        
        # Detectar tipo de OS
        if re.search(r'Windows', prompt, re.IGNORECASE):
            metricas['os_type'] = 'Windows'
        else:
            metricas['os_type'] = 'Linux'
    except Exception as e:
        print(f"Error extrayendo métricas: {e}")
    return metricas

# -----------------------------
# Endpoint principal
# -----------------------------
@app.post("/analizar-sistema", response_model=Dict[str, Any])
async def analizar_sistema(request: PromptRequest):
    try:
        if model is None or tokenizer is None:
            raise HTTPException(status_code=500, detail="Modelo no cargado")

        # Prompt mejorado para análisis completo y recomendaciones
        input_text = f"""
You are an expert system administrator and cybersecurity analyst.
Analyze the following system health report (Linux or Windows).
Provide a JSON with the following fields:
- summary
- cpu_analysis
- memory_analysis
- processes_issues
- firewall_ports
- active_users
- recommendations

Ensure the JSON is valid and properly structured.
Here is the report:
{request.prompt}
"""

        # Tokenización
        inputs = tokenizer(input_text, return_tensors="pt", truncation=True, max_length=2048, padding=True)
        inputs = {k: v.to(model.device) for k, v in inputs.items()}

        # Generación
        with torch.no_grad():
            outputs = model.generate(
                inputs["input_ids"],
                max_length=2000,
                num_beams=3,
                early_stopping=True
            )

        respuesta = tokenizer.decode(outputs[0], skip_special_tokens=True)

        # Intentar parsear JSON del modelo
        try:
            analisis_detallado = json.loads(respuesta)
        except Exception:
            analisis_detallado = {"raw_text": respuesta}

        metricas = extraer_metricas_del_prompt(request.prompt)

        return {
            "analisis_detallado": analisis_detallado,
            "metricas_extraidas": metricas,
            "timestamp": datetime.now().isoformat()
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# -----------------------------
# Endpoint de health check
# -----------------------------
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "tokenizer_loaded": tokenizer is not None,
        "timestamp": datetime.now().isoformat()
    }