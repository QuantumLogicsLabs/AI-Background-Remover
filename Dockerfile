FROM python:3.11-slim

ARG USE_GPU=false

RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip \
 && if [ "$USE_GPU" = "true" ]; then \
        sed -i 's|whl/cpu|whl/cu121|g' requirements.txt \
     && sed -i 's/+cpu/+cu121/g' requirements.txt \
     && sed -i 's/^onnxruntime==.*/# onnxruntime (replaced by gpu build)/' requirements.txt \
     && sed -i 's/^# onnxruntime-gpu/onnxruntime-gpu/' requirements.txt; \
    fi \
 && pip install --no-cache-dir -r requirements.txt

COPY backend/ ./backend/
COPY AI/      ./AI/

RUN mkdir -p backend/uploads backend/output

ENV MODEL_BACKEND=rembg \
    DEFAULT_QUALITY=fast \
    ONNX_MODEL_PATH=AI/models/model.onnx \
    TORCH_MODEL_PATH=AI/models/model.pth \
    MONGO_URI=mongodb://mongo:27017 \
    MONGO_DB_NAME=ai_bg_remover \
    ACCESS_TOKEN_EXPIRE_MINUTES=60 \
    REFRESH_TOKEN_EXPIRE_DAYS=30 \
    COOKIE_SECURE=true \
    COOKIE_SAMESITE=none \
    DAILY_QUOTA_LIMIT=100 \
    FILE_MAX_AGE_HOURS=24 \
    CLEANUP_INTERVAL_MINS=60 \
    AI_PROVIDER=gemini \
    PORT=8000

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')" || exit 1

CMD ["uvicorn", "backend.app:app", "--host", "0.0.0.0", "--port", "8000"]
