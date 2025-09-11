import os
import re
import json
from typing import Dict, Any, List
from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import torch
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM

# Configurar FastAPI
app = FastAPI(title="AI System Analysis API", version="1.0.0")

# Configurar CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Definir modelo de entrada
class PromptRequest(BaseModel):
    prompt: str
    user_id: str = "anonymous"
    model_name: str = "google/flan-t5-large"

# Variables globales
model = None
tokenizer = None


def load_model(model_name="google/flan-t5-large"):
    """Cargar modelo Flan-T5 en GPU si está disponible"""
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


def extraer_metricas_del_prompt(prompt: str) -> Dict[str, Any]:
    """Extraer métricas específicas del texto del prompt"""
    metricas = {}
    try:
        cpu_match = re.search(r'CPU utilization:\s*([\d.]+)%', prompt, re.IGNORECASE)
        if cpu_match:
            metricas['cpu_utilization_percent'] = float(cpu_match.group(1))

        mem_total_match = re.search(r'Total memory:\s*(\d+)\s*MB', prompt, re.IGNORECASE)
        mem_avail_match = re.search(r'Available memory:\s*(\d+)\s*MB', prompt, re.IGNORECASE)
        if mem_total_match and mem_avail_match:
            total = int(mem_total_match.group(1))
            available = int(mem_avail_match.group(1))
            metricas['memory_total_mb'] = total
            metricas['memory_available_mb'] = available
            metricas['memory_utilization_percent'] = ((total - available) / total) * 100
    except Exception as e:
        print(f"Error extrayendo métricas: {e}")
    return metricas


@app.post("/analizar-sistema", response_model=Dict[str, Any])
async def analizar_sistema(request: PromptRequest):
    """Endpoint para analizar métricas del sistema"""
    try:
        if model is None or tokenizer is None:
            raise HTTPException(status_code=500, detail="Modelo no cargado")

        input_text = f"Analyze this Linux system health report:\n\n{request.prompt}"
        inputs = tokenizer(input_text, return_tensors="pt", truncation=True, max_length=1024, padding=True)
        inputs = {k: v.to(model.device) for k, v in inputs.items()}

        with torch.no_grad():
            outputs = model.generate(inputs["input_ids"], max_length=600)
            #outputs = model.generate(inputs["input_ids"], max_length=600, temperature=0.4)

        respuesta = tokenizer.decode(outputs[0], skip_special_tokens=True)
        metricas = extraer_metricas_del_prompt(request.prompt)

        return {
            "analisis_detallado": respuesta,
            "metricas_extraidas": metricas,
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health_check():
    """Endpoint de health check"""
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "tokenizer_loaded": tokenizer is not None,
        "timestamp": datetime.now().isoformat()
    }