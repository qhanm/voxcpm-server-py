#!/bin/bash
# =============================================================================
# VoxCPM2 Server - Start Script
# =============================================================================
# Auto-loads .env file if exists, then starts uvicorn server.
#
# Usage:
#   bash start.sh                    # Run in foreground
#   bash start.sh --daemon           # Run as background daemon
#   bash start.sh -d                 # Same as --daemon
#
# Environment loading priority (later overrides earlier):
#   1. .env file (if exists)
#   2. Shell environment variables
#   3. Command line (export VAR=value bash start.sh)
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# -----------------------------------------------------------------------------
# Load .env file if exists
# -----------------------------------------------------------------------------
if [ -f ".env" ]; then
    log "Loading .env file..."
    
    # Export all variables from .env (handle comments and empty lines)
    set -a   # Auto-export all variables
    # shellcheck disable=SC1091
    source <(grep -v '^#' .env | grep -v '^$' | sed 's/^/export /')
    set +a
    
    success ".env loaded"
else
    warn ".env file not found, using shell environment"
fi

# -----------------------------------------------------------------------------
# Validate required variables
# -----------------------------------------------------------------------------
if [ -z "${API_KEY:-}" ]; then
    error "API_KEY is required. Set in .env file or run: export API_KEY=\"\$(openssl rand -hex 32)\""
fi

if [ "${API_KEY}" = "change-me-in-production" ] || [ "${API_KEY}" = "change-me-to-strong-random-string" ]; then
    error "API_KEY is using default placeholder. Generate a real one: openssl rand -hex 32"
fi

if [ ${#API_KEY} -lt 16 ]; then
    warn "API_KEY is short (${#API_KEY} chars). Recommend at least 32 chars: openssl rand -hex 32"
fi

# -----------------------------------------------------------------------------
# Set defaults for optional variables
# -----------------------------------------------------------------------------
export MODEL_PATH="${MODEL_PATH:-$SCRIPT_DIR/models/VoxCPM2}"
export VOICE_LIBRARY_DIR="${VOICE_LIBRARY_DIR:-$SCRIPT_DIR/voice_library}"
export OUTPUTS_DIR="${OUTPUTS_DIR:-$SCRIPT_DIR/outputs}"
export CACHE_DIR="${CACHE_DIR:-$SCRIPT_DIR/cache}"
export LOAD_DENOISER="${LOAD_DENOISER:-false}"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export PORT="${PORT:-8000}"
export HOST="${HOST:-0.0.0.0}"

# Create dirs (must succeed)
mkdir -p "$VOICE_LIBRARY_DIR" "$OUTPUTS_DIR" "$CACHE_DIR" 2>/dev/null || \
    warn "Failed to create some directories"

# Try to create log directory
mkdir -p /var/log 2>/dev/null || true

# -----------------------------------------------------------------------------
# Verify model exists
# -----------------------------------------------------------------------------
if [ ! -d "$MODEL_PATH" ] || [ -z "$(ls -A "$MODEL_PATH" 2>/dev/null)" ]; then
    warn "Model not found at: $MODEL_PATH"
    warn "Server will try to download from HuggingFace on startup (~5GB)"
    warn "Recommend running 'bash setup.sh' first to download model"
fi

# -----------------------------------------------------------------------------
# Show configuration
# -----------------------------------------------------------------------------
echo ""
log "=== VoxCPM2 Server Starting ==="
log "Working dir:        $SCRIPT_DIR"
log "Host:               $HOST:$PORT"
log "Model path:         $MODEL_PATH"
log "Voice library:      $VOICE_LIBRARY_DIR"
log "Outputs dir:        $OUTPUTS_DIR"
log "Log level:          $LOG_LEVEL"
log "Load denoiser:      $LOAD_DENOISER"
log "API key:            ${API_KEY:0:8}...***${API_KEY: -4}"
echo ""

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
DAEMON_MODE=false
for arg in "$@"; do
    case "$arg" in
        --daemon|-d)
            DAEMON_MODE=true
            ;;
        --help|-h)
            echo "Usage: $0 [--daemon|-d]"
            echo ""
            echo "Options:"
            echo "  --daemon, -d    Run server in background (daemon mode)"
            echo "  --help, -h      Show this help"
            echo ""
            echo "Environment variables (set in .env or export):"
            echo "  API_KEY              (required) Strong random API key"
            echo "  PORT                 Server port (default: 8000)"
            echo "  HOST                 Bind address (default: 0.0.0.0)"
            echo "  MODEL_PATH           Path to VoxCPM2 model"
            echo "  LOG_LEVEL            DEBUG / INFO / WARNING / ERROR"
            echo "  LOAD_DENOISER        true / false"
            exit 0
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Run server
# -----------------------------------------------------------------------------
if [ "$DAEMON_MODE" = true ]; then
    LOG_FILE="${LOG_FILE:-/var/log/voxcpm-server.log}"
    PID_FILE="${PID_FILE:-/tmp/voxcpm-server.pid}"
    
    # Try fallback log location if /var/log not writable
    if ! touch "$LOG_FILE" 2>/dev/null; then
        LOG_FILE="$SCRIPT_DIR/voxcpm-server.log"
        warn "Cannot write to /var/log, using $LOG_FILE"
    fi
    
    # Check if already running
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        error "Server already running (PID: $(cat "$PID_FILE")). Stop with: bash stop.sh"
    fi
    
    log "Starting in DAEMON mode..."
    log "Log file: $LOG_FILE"
    log "PID file: $PID_FILE"
    
    nohup uvicorn server:app \
        --host "$HOST" \
        --port "$PORT" \
        --workers 1 \
        --log-level "${LOG_LEVEL,,}" \
        > "$LOG_FILE" 2>&1 &
    
    SERVER_PID=$!
    echo "$SERVER_PID" > "$PID_FILE"
    
    log "Server started, PID: $SERVER_PID"
    log "Logs: tail -f $LOG_FILE"
    log "Stop: bash stop.sh"
    
    # Wait a bit and verify it's still alive
    sleep 3
    if kill -0 "$SERVER_PID" 2>/dev/null; then
        success "Server is running"
        log "Run 'bash health-check.sh' to wait for model load complete"
    else
        echo ""
        error "Server failed to start. Last log lines:"
        tail -30 "$LOG_FILE"
        exit 1
    fi
else
    log "Starting in FOREGROUND mode (Ctrl+C to stop)..."
    echo ""
    exec uvicorn server:app \
        --host "$HOST" \
        --port "$PORT" \
        --workers 1 \
        --log-level "${LOG_LEVEL,,}"
fi
