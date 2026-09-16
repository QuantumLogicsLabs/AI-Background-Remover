# ============================================================
# AI Background Remover — Docker image
# Builds the FastAPI backend together with the AI pipeline.
#
# CPU build (default):
#   docker build -t ai-bg-remover .
#
# GPU build (CUDA 12.1):
#   docker build --build-arg USE_GPU=true -t ai-bg-remover-gpu .
# ============================================================

# ---- Base image -----------------------------------------------
FROM python:3.11-slim

# ---- Build args -----------------------------------------------
# Set USE_GPU=true at build time to swap onnxruntime → onnxruntime-gpu
ARG USE_GPU=false

# ---- System dependencies --------------------------------------
# libgl1 + libglib2.0-0  — required by OpenCV
# libgomp1               — required by onnxruntime
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# ---- Working directory ----------------------------------------
WORKDIR /app

# ---- Python dependencies --------------------------------------
# Copy requirements first to leverage Docker layer caching.
COPY requirements.txt .

# Install deps; swap onnxruntime and torch for GPU variant when requested
RUN pip install --no-cache-dir --upgrade pip \
 && if [ "$USE_GPU" = "true" ]; then \
        sed -i 's|whl/cpu|whl/cu121|g' requirements.txt \
     && sed -i 's/+cpu/+cu121/g' requirements.txt \
     && sed -i 's/^onnxruntime==.*/# onnxruntime (replaced by gpu build)/' requirements.txt \
     && sed -i 's/^# onnxruntime-gpu/onnxruntime-gpu/' requirements.txt; \
    fi \
 && pip install --no-cache-dir -r requirements.txt

# ---- Application source ---------------------------------------
# The AI submodule is checked out locally as "AI/" — copy it in.
COPY backend/ ./backend/
COPY AI/      ./AI/

# ---- Runtime directories (mount via volume in production) -----
RUN mkdir -p backend/uploads backend/output

# ---- Environment defaults -------------------------------------
# Override any of these at runtime with -e flags or a .env file.
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

# ---- Expose API port ------------------------------------------
EXPOSE 8000

# ---- Health check ---------------------------------------------
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')" || exit 1

# ---- Start server ---------------------------------------------
# Run from /app so relative imports (AI/, backend/) resolve correctly.
CMD ["uvicorn", "backend.app:app", "--host", "0.0.0.0", "--port", "8000"]
