#!/usr/bin/env bash
# Production entrypoint for OmniRoute on Hugging Face Spaces.
# Coordinates database hydration, periodic background sync, and graceful shutdown.
set -eo pipefail

echo "=========================================================="
echo " Starting OmniRoute on Hugging Face Spaces"
echo "=========================================================="

# 1. Download existing database from Hugging Face Dataset if configured
if [ -n "$HF_TOKEN" ] && [ -n "$HF_DATASET_ID" ]; then
    echo "[Entrypoint] Checking Hugging Face Dataset for existing database..."
    python3 /app/hf_sync.py download || echo "[Entrypoint] Initial download warning, proceeding with launch..."

    # Start the background sync loop (uploads backups periodically)
    python3 /app/hf_sync.py loop &
    SYNC_LOOP_PID=$!
    echo "[Entrypoint] Background sync loop started with PID ${SYNC_LOOP_PID}."
else
    echo "[Entrypoint] Note: HF_TOKEN or HF_DATASET_ID not configured."
    echo "[Entrypoint] Running in standalone ephemeral mode without dataset sync."
fi

# 2. Trap termination signals for a graceful final database upload
cleanup() {
    echo ""
    echo "[Entrypoint] Received termination signal (SIGTERM/SIGINT)."
    if [ -n "$HF_TOKEN" ] && [ -n "$HF_DATASET_ID" ]; then
        echo "[Entrypoint] Performing final database sync to dataset..."
        python3 /app/hf_sync.py upload || echo "[Entrypoint] Final sync failed."
    fi

    if [ -n "$PINGER_PID" ]; then
        kill "$PINGER_PID" 2>/dev/null || true
    fi
    if [ -n "$SYNC_LOOP_PID" ]; then
        kill "$SYNC_LOOP_PID" 2>/dev/null || true
    fi

    if [ -n "$APP_PID" ]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    echo "[Entrypoint] Cleanup complete. Exiting."
    exit 0
}

trap cleanup SIGTERM SIGINT


# 3. Background Keep-Alive Self-Pinger (runs every 9 minutes to keep Render active)
start_self_pinger() {
    echo "[Entrypoint] Starting 9-minute self-ping keep-alive loop..."
    while true; do
        sleep 540
        echo "[KeepAlive] Sending self-ping to prevent sleep..."
        curl -s -f -m 20 "https://omniroute-ai-5hys.onrender.com/api/monitoring/health" >/dev/null 2>&1 || true
    done
}
start_self_pinger &
PINGER_PID=$!

# 4. Start OmniRoute Standalone Server
echo "[Entrypoint] Launching OmniRoute server on port ${PORT:-20128}..."
node dev/run-standalone.mjs &
APP_PID=$!

# Wait for process so trap signals are handled cleanly
wait "$APP_PID"

