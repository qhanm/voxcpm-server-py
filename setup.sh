#!/bin/bash
# =============================================================================
# VoxCPM2 Server - Setup Script
# =============================================================================
# Usage on GPU server (Template 4 - PyTorch 2.5.1 CUDA 12.4):
#   bash setup.sh                 # Full setup (install + download model)
#   bash setup.sh --skip-model    # Skip model download (manual later)
#   bash setup.sh --skip-deps     # Skip pip install (already installed)
#
# This script will:
#   0. Create .env file if not exists (with auto-generated API_KEY)
#   1. Verify PyTorch + CUDA available
#   2. Install system dependencies (libsndfile, ffmpeg)
#   3. Install Python dependencies (locked versions)
#   4. Verify imports work
#   5. Download VoxCPM2 model from HuggingFace (~5GB)
# =============================================================================

set -e
set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] ✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ✗${NC} $1" >&2
    exit 1
}

# Parse arguments
SKIP_MODEL=false
SKIP_DEPS=false
for arg in "$@"; do
    case "$arg" in
        --skip-model) SKIP_MODEL=true ;;
        --skip-deps) SKIP_DEPS=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-model] [--skip-deps]"
            exit 0
            ;;
    esac
done

# Track timing
START_TIME=$(date +%s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
log "=== VoxCPM2 Server Setup ==="
log "Working directory: $SCRIPT_DIR"
echo ""

# -----------------------------------------------------------------------------
# Step 0: Setup .env file
# -----------------------------------------------------------------------------
log "[0/5] Setting up .env file..."

if [ ! -f ".env" ]; then
    if [ -f "init-env.sh" ]; then
        chmod +x init-env.sh
        bash init-env.sh
    else
        warn "init-env.sh not found, creating .env manually"
        
        # Generate API key
        if command -v openssl &> /dev/null; then
            API_KEY=$(openssl rand -hex 32)
        else
            API_KEY=$(head -c 32 /dev/urandom | xxd -p -c 64)
        fi
        
        cat > .env << EOF
API_KEY=${API_KEY}
HOST=0.0.0.0
PORT=8000
LOG_LEVEL=INFO
MODEL_PATH=./models/VoxCPM2
VOICE_LIBRARY_DIR=./voice_library
OUTPUTS_DIR=./outputs
CACHE_DIR=./cache
LOAD_DENOISER=false
EOF
        chmod 600 .env
        success ".env created with auto-generated API_KEY: ${API_KEY:0:8}..."
    fi
else
    success ".env already exists, keeping current values"
fi

# Load .env to use during setup
set -a
source <(grep -v '^#' .env | grep -v '^$' | sed 's/^/export /')
set +a

echo ""

# -----------------------------------------------------------------------------
# Step 1: Verify environment
# -----------------------------------------------------------------------------
log "[1/5] Verifying environment..."

# Check Python — install if missing
if ! command -v python3 &> /dev/null; then
    warn "python3 not found, attempting to install..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq python3 python3-pip || error "Failed to install python3"
    else
        error "Python 3 not found and cannot auto-install (no apt-get)"
    fi
fi
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
success "Python: $PYTHON_VERSION"

# Check PyTorch
PYTORCH_INFO=$(python3 -c "
import torch
print(f'{torch.__version__}|{torch.version.cuda}|{torch.cuda.is_available()}|{torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')
" 2>/dev/null) || error "PyTorch not found. Use Template 4 (PyTorch 2.5.1 CUDA 12.4)"

IFS='|' read -r TORCH_VER CUDA_VER CUDA_AVAIL GPU_NAME <<< "$PYTORCH_INFO"

success "PyTorch: $TORCH_VER (CUDA $CUDA_VER)"

if [ "$CUDA_AVAIL" != "True" ]; then
    error "CUDA not available! Cannot run VoxCPM2 without GPU"
fi
success "GPU: $GPU_NAME"

if [[ ! "$TORCH_VER" =~ ^2\.5\. ]]; then
    warn "PyTorch version is $TORCH_VER, expected 2.5.x"
    warn "VoxCPM2 may have compatibility issues. Continue? (5s to abort)"
    sleep 5
fi

echo ""

# -----------------------------------------------------------------------------
# Step 2: System dependencies
# -----------------------------------------------------------------------------
log "[2/5] Installing system dependencies..."

if command -v apt-get &> /dev/null; then
    apt-get update -qq 2>&1 | tail -5 || warn "apt-get update had warnings"
    
    apt-get install -y -qq \
        python3 \
        python3-pip \
        libsndfile1 \
        ffmpeg \
        curl \
        git \
        ca-certificates \
        2>&1 | tail -5 || warn "Some packages failed to install"
    
    success "System dependencies installed"
else
    warn "apt-get not found, skipping system deps"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 3: Python dependencies
# -----------------------------------------------------------------------------
if [ "$SKIP_DEPS" = true ]; then
    log "[3/5] Skipping Python deps (--skip-deps)"
else
    log "[3/5] Installing Python dependencies..."
    
    if [ ! -f "requirements.txt" ]; then
        error "requirements.txt not found"
    fi
    
    pip install --quiet --upgrade pip 2>&1 | tail -3 || warn "Pip upgrade had warnings"
    
    MAX_RETRIES=3
    RETRY=0
    while [ $RETRY -lt $MAX_RETRIES ]; do
        if pip install --no-cache-dir -r requirements.txt; then
            success "Python dependencies installed"
            break
        else
            RETRY=$((RETRY + 1))
            if [ $RETRY -lt $MAX_RETRIES ]; then
                warn "pip install failed, retrying ($RETRY/$MAX_RETRIES)..."
                sleep 10
            else
                error "Failed to install Python deps after $MAX_RETRIES attempts"
            fi
        fi
    done
fi

echo ""

# -----------------------------------------------------------------------------
# Step 4: Verify imports
# -----------------------------------------------------------------------------
log "[4/5] Verifying imports..."

python3 << 'EOF' || error "Import verification failed"
import sys

required_imports = [
    ("voxcpm", "VoxCPM"),
    ("fastapi", "FastAPI"),
    ("uvicorn", None),
    ("soundfile", None),
    ("loguru", "logger"),
    ("transformers", None),
    ("torch", None),
]

failed = []
for module_name, attr in required_imports:
    try:
        module = __import__(module_name, fromlist=[attr] if attr else [])
        if attr:
            getattr(module, attr)
        print(f"  ✓ {module_name}")
    except Exception as e:
        print(f"  ✗ {module_name}: {e}")
        failed.append(module_name)

if failed:
    print(f"\nFailed imports: {failed}")
    sys.exit(1)

print("\n✓ All imports OK")
EOF

success "Imports verified"
echo ""

# -----------------------------------------------------------------------------
# Step 5: Download model
# -----------------------------------------------------------------------------
if [ "$SKIP_MODEL" = true ]; then
    log "[5/5] Skipping model download (--skip-model)"
    warn "Server will download model on first start"
else
    log "[5/5] Downloading VoxCPM2 model (~5GB)..."
    
    MODEL_PATH="${MODEL_PATH:-./models/VoxCPM2}"
    
    if [ -d "$MODEL_PATH" ] && [ "$(ls -A "$MODEL_PATH" 2>/dev/null)" ]; then
        warn "Model already exists at $MODEL_PATH"
        warn "Skipping download. Delete folder and re-run to force download."
    else
        mkdir -p "$(dirname "$MODEL_PATH")"
        
        python3 << EOF || error "Model download failed"
from huggingface_hub import snapshot_download
import time

print("Downloading openbmb/VoxCPM2 from HuggingFace...")
start = time.time()

snapshot_download(
    repo_id="openbmb/VoxCPM2",
    local_dir="$MODEL_PATH",
    local_dir_use_symlinks=False,
    resume_download=True,
)

duration = time.time() - start
print(f"✓ Model downloaded in {duration:.1f}s")
EOF
        
        success "Model downloaded to $MODEL_PATH"
    fi
fi

echo ""

# =============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

success "=== Setup completed in ${MINUTES}m ${SECONDS}s ==="
echo ""
log "Configuration saved to: $SCRIPT_DIR/.env"
log ""
log "Next steps:"
log "  Start server:   bash start.sh --daemon"
log "  Health check:   bash health-check.sh"
log "  Stop server:    bash stop.sh"
log "  View API key:   grep API_KEY .env"
echo ""
