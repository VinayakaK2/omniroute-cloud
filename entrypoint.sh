#!/usr/bin/env bash
set -eo pipefail

echo "=========================================================="
echo " Starting OmniRoute Cloud Runner (Memory Optimized)"
echo "=========================================================="

export OMNIROUTE_MEMORY_MB=180
export NODE_OPTIONS="--require /app/patch_pressure.cjs --max-old-space-size=180 ${NODE_OPTIONS:-}"
export OMNIROUTE_PRESSURE_PSI_DISABLED="true"

# 1. Download existing database from Hugging Face Dataset if configured
if [ -n "$HF_TOKEN" ] && [ -n "$HF_DATASET_ID" ]; then
    echo "[Entrypoint] Checking Hugging Face Dataset for existing database..."
    python3 /app/hf_sync.py download || echo "[Entrypoint] Initial download warning, proceeding with launch..."
    chmod 666 /app/data/*.sqlite 2>/dev/null || true
    chmod -R 777 /app/data 2>/dev/null || true

    # Periodic background database sync loop (invokes Python on demand and exits, 0 MB persistent RAM)
    run_periodic_sync() {
        while true; do
            sleep 1800
            echo "[Storage] Periodic database backup starting..."
            python3 /app/hf_sync.py upload || echo "[Storage] Periodic backup warning"
        done
    }
    run_periodic_sync &
    SYNC_LOOP_PID=$!
    echo "[Entrypoint] Background dataset sync loop started (on-demand)."
fi

# 2. Start zero-RAM 5-minute keep-alive self-pinger using curl
run_keepalive() {
    local target_url="${SELF_PING_URL:-https://omniroute-ai-5hys.onrender.com/api/monitoring/health}"
    local interval="${PING_INTERVAL_SECONDS:-300}"
    echo "[KeepAlive] Zero-RAM keep-alive active for $target_url (every ${interval}s)"
    sleep 35
    while true; do
        if curl -s -f -A "OmniRoute-KeepAlive/1.0" --max-time 15 "$target_url" > /dev/null 2>&1; then
            echo "[KeepAlive] $(date '+%Y-%m-%d %H:%M:%S UTC') Ping to $target_url -> HTTP 200 OK"
        else
            echo "[KeepAlive] $(date '+%Y-%m-%d %H:%M:%S UTC') Ping attempt failed (will retry in ${interval}s)"
        fi
        sleep "$interval"
    done
}
run_keepalive &
PINGER_PID=$!
echo "[Entrypoint] Zero-RAM keep-alive pinger started."

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

# 4. Start OmniRoute Standalone Server with memory patch
echo "[Entrypoint] Launching OmniRoute server on port ${PORT:-20128} with NODE_OPTIONS="$NODE_OPTIONS"..."
node dev/run-standalone.mjs &
APP_PID=$!

wait "$APP_PID"
