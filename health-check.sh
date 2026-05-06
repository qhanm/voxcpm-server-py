#!/bin/bash
# =============================================================================
# VoxCPM2 Server - Health Check Script
# =============================================================================
# Wait for server to become ready, with timeout
# Usage:
#   bash health-check.sh                # Wait up to 5 minutes
#   bash health-check.sh 60             # Wait up to 60 seconds
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PORT="${PORT:-8000}"
HOST="${HEALTH_HOST:-localhost}"
URL="http://${HOST}:${PORT}/health"
MAX_WAIT="${1:-300}"  # Default 5 minutes
INTERVAL=5
ELAPSED=0

echo "Health checking $URL (timeout: ${MAX_WAIT}s)..."
echo ""

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Try to fetch health endpoint
    RESPONSE=$(curl -sf -m 5 "$URL" 2>/dev/null) || RESPONSE=""
    
    if [ -n "$RESPONSE" ]; then
        # Check if model is loaded
        MODEL_LOADED=$(echo "$RESPONSE" | grep -o '"model_loaded":[^,}]*' | head -1 | cut -d: -f2 | tr -d ' ')
        
        if [ "$MODEL_LOADED" = "true" ]; then
            echo -e "${GREEN}✓ Server ready (after ${ELAPSED}s)${NC}"
            echo ""
            echo "Response:"
            echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
            exit 0
        else
            echo -e "${YELLOW}[${ELAPSED}s] Server up but model still loading...${NC}"
        fi
    else
        echo "[${ELAPSED}s] Waiting for server to respond..."
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""
echo -e "${RED}✗ Server failed to become ready after ${MAX_WAIT}s${NC}"
echo ""
echo "Last 50 lines of log:"
echo "----------------------------------------"
LOG_FILE="${LOG_FILE:-/var/log/voxcpm-server.log}"
if [ -f "$LOG_FILE" ]; then
    tail -50 "$LOG_FILE"
else
    echo "Log file not found: $LOG_FILE"
fi
exit 1
