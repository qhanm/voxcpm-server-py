#!/bin/bash
# =============================================================================
# VoxCPM2 Server - Stop Script
# =============================================================================

PID_FILE="${PID_FILE:-/tmp/voxcpm-server.pid}"

if [ ! -f "$PID_FILE" ]; then
    echo "PID file not found: $PID_FILE"
    echo "Server may not be running, or was started in foreground mode."
    
    # Try to find by process name
    PIDS=$(pgrep -f "uvicorn server:app" || true)
    if [ -n "$PIDS" ]; then
        echo "Found uvicorn processes: $PIDS"
        echo "Killing..."
        kill $PIDS
        echo "✓ Killed"
    fi
    exit 0
fi

PID=$(cat "$PID_FILE")

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Process $PID not running, cleaning up PID file"
    rm -f "$PID_FILE"
    exit 0
fi

echo "Stopping server (PID: $PID)..."
kill "$PID"

# Wait for graceful shutdown
for i in $(seq 1 10); do
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "✓ Server stopped"
        rm -f "$PID_FILE"
        exit 0
    fi
    sleep 1
done

# Force kill if still running
echo "Server didn't stop gracefully, force killing..."
kill -9 "$PID" 2>/dev/null || true
rm -f "$PID_FILE"
echo "✓ Server force stopped"
