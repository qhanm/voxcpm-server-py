#!/bin/bash
# =============================================================================
# VoxCPM2 Server - Initialize .env file
# =============================================================================
# Creates .env file with auto-generated API_KEY and sensible defaults.
# Run this ONCE after cloning the repo.
#
# Usage:
#   bash init-env.sh                # Create .env if not exists
#   bash init-env.sh --force        # Overwrite existing .env
#   bash init-env.sh --print        # Print to stdout (don't save)
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

FORCE=false
PRINT_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE=true
            ;;
        --print|-p)
            PRINT_ONLY=true
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--print]"
            echo ""
            echo "  --force, -f    Overwrite existing .env file"
            echo "  --print, -p    Print to stdout instead of saving"
            exit 0
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Check existing .env
# -----------------------------------------------------------------------------
if [ -f "$ENV_FILE" ] && [ "$FORCE" = false ] && [ "$PRINT_ONLY" = false ]; then
    echo -e "${YELLOW}⚠ .env already exists${NC}"
    echo "  Path: $ENV_FILE"
    echo ""
    echo "  Use --force to overwrite, or --print to view current values"
    echo ""
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# Generate API key
# -----------------------------------------------------------------------------
if command -v openssl &> /dev/null; then
    API_KEY=$(openssl rand -hex 32)
elif [ -f /dev/urandom ]; then
    API_KEY=$(head -c 32 /dev/urandom | xxd -p -c 64)
else
    echo -e "${RED}✗ Cannot generate API key (need openssl or /dev/urandom)${NC}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Generate .env content
# -----------------------------------------------------------------------------
ENV_CONTENT=$(cat << EOF
# =============================================================================
# VoxCPM2 Server Configuration
# Auto-generated on $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================
# IMPORTANT: 
# - Keep this file secret (not committed to Git)
# - Save API_KEY for backend orchestrator integration
# =============================================================================

# --- Required ---
API_KEY=${API_KEY}

# --- Server ---
HOST=0.0.0.0
PORT=8000
LOG_LEVEL=INFO

# --- Paths ---
MODEL_PATH=./models/VoxCPM2
VOICE_LIBRARY_DIR=./voice_library
OUTPUTS_DIR=./outputs
CACHE_DIR=./cache

# --- Optional features ---
LOAD_DENOISER=false

# --- Daemon mode (when using start.sh --daemon) ---
LOG_FILE=/var/log/voxcpm-server.log
PID_FILE=/tmp/voxcpm-server.pid
EOF
)

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------
if [ "$PRINT_ONLY" = true ]; then
    echo "$ENV_CONTENT"
else
    echo "$ENV_CONTENT" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"  # Read/write for owner only
    
    echo -e "${GREEN}✓ .env file created${NC}"
    echo "  Path: $ENV_FILE"
    echo "  Permissions: 600 (owner read/write only)"
    echo ""
    echo "API_KEY (save this for backend integration):"
    echo "  ${API_KEY}"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'bash setup.sh' to install dependencies + download model"
    echo "  2. Run 'bash start.sh --daemon' to start server"
    echo "  3. Run 'bash health-check.sh' to verify it's ready"
fi
