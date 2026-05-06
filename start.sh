#!/bin/bash
# =============================================================================
# VoxCPM2 Server - Start Script
# =============================================================================
# Usage:
#   bash start.sh                    # Run in foreground
#   bash start.sh --daemon           # Run as background daemon
#   nohup bash start.sh > server.log 2>&1 &   # Manual daemon
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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# -----------------------------------------------------------------------------
# Validate environment
# -----------------------------------------------------------------------------
if [ -z "${API_KEY:-}" ]; then
    echo -e "${RED}✗ API_KEY environment variable is required${NC}"
    echo "Generate one with: export API_KEY=\"\$(openssl rand -hex 32)\""
    exit 1
fi

if [ "${API_KEY}" = "change-me-in-production" ]; then
    echo -e "${RED}✗ Please change API_KEY from default value${NC}"
    exit 1
fi

# Set defaults
export MODEL_PATH="${MODEL_PATH:-$SCRIPT_DIR/models/VoxCPM2}"
export VOICE_LIBRARY_DIR="${VOICE_LIBRARY_DIR:-$SCRIPT_DIR/voice_library}"
export OUTPUTS_DIR="${OUTPUTS_DIR:-$SCRIPT_DIR/outputs}"
export CACHE_DIR="${CACHE_DIR:-$SCRIPT_DIR/cache}"
export LOAD_DENOISER="${LOAD_DENOISER:-false}"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export PORT="${PORT:-8000}"
export HOST="${HOST:-0.0.0.0}"

# Create dirs
mkdir -p "$VOICE_LIBRARY_DIR" "$OUTPUTS_DIR" "$CACHE_DIR" /var/log

# Verify model exists
if [ ! -d "$MODEL_PATH" ] || [ -z "$(ls -A "$MODEL_PATH" 2>/dev/null)" ]; then
    echo -e "${YELLOW}⚠ Model not found at $MODEL_PATH${NC}"
    echo "Run setup.sh first, or model will download on first start."
fi

# -----------------------------------------------------------------------------
# Show config
# -----------------------------------------------------------------------------
log "=== VoxCPM2 Server Starting ==="
log "Host:              $HOST:$PORT"
log "Model path:        $MODEL_PATH"
log "Voice library:     $VOICE_LIBRARY_DIR"
log "Outputs dir:       $OUTPUTS_DIR"
log "Log level:         $LOG_LEVEL"
log "API key:           ${API_KEY:0:8}...***"
echo ""

# -----------------------------------------------------------------------------
# Run server
# -----------------------------------------------------------------------------
DAEMON_MODE=false
for arg in "$@"; do
    if [ "$arg" = "--daemon" ] || [ "$arg" = "-d" ]; then
        DAEMON_MODE=true
    fi
done

if [ "$DAEMON_MODE" = true ]; then
    log "Starting in daemon mode..."
    LOG_FILE="${LOG_FILE:-/var/log/voxcpm-server.log}"
    PID_FILE="${PID_FILE:-/tmp/voxcpm-server.pid}"
    
    # Check if already running
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo -e "${RED}✗ Server already running (PID: $(cat "$PID_FILE"))${NC}"
        exit 1
    fi
    
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
    log "Stop: bash stop.sh  (or kill \$(cat $PID_FILE))"
    
    # Wait a bit and verify it's still alive
    sleep 3
    if kill -0 "$SERVER_PID" 2>/dev/null; then
        echo -e "${GREEN}✓ Server is running${NC}"
    else
        echo -e "${RED}✗ Server failed to start. Check logs: $LOG_FILE${NC}"
        tail -20 "$LOG_FILE"
        exit 1
    fi
else
    log "Starting in foreground mode (Ctrl+C to stop)..."
    exec uvicorn server:app \
        --host "$HOST" \
        --port "$PORT" \
        --workers 1 \
        --log-level "${LOG_LEVEL,,}"
fi
