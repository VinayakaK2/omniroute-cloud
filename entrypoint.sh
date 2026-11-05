#!/usr/bin/env bash
set -eo pipefail

echo "=========================================================="
echo " Starting OmniRoute Cloud Runner"
echo "=========================================================="

# 1. Download existing database from Hugging Face Dataset if configured
if [ -n "$HF_TOKEN" ] && [ -n "$HF_DATASET_ID" ]; then
    echo "[Entrypoint] Checking Hugging Face Dataset for existing database..."
    python3 /app/hf_sync.py download || echo "[Entrypoint] Initial download warning, proceeding with launch..."

    # Start the background sync loop (uploads backups periodically)
    python3 /app/hf_sync.py loop &
    SYNC_LOOP_PID=$!
    echo "[Entrypoint] Background dataset sync loop started."
fi

# 2. Start internal 9-minute self-pinger
python3 /app/pinger.py &
PINGER_PID=$!
echo "[Entrypoint] Keep-alive self-pinger started."

# 3. Trap termination signals for a graceful final database upload
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

# 4. Start OmniRoute Standalone Server
echo "[Entrypoint] Launching OmniRoute server on port ${PORT:-20128}..."
node dev/run-standalone.mjs &
APP_PID=$!

wait "$APP_PID"
