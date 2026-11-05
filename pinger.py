"""
OmniRoute Keep-Alive Background Service.
Pings the public health endpoint every 9 minutes to keep Render container active.
"""
import os
import sys
import time
import urllib.request
import ssl

HEALTH_URL = "https://omniroute-ai-5hys.onrender.com/api/monitoring/health"
INTERVAL = int(os.getenv("PING_INTERVAL_SEC", "540"))  # 9 minutes

ctx = ssl.create_default_context()

def ping():
    try:
        req = urllib.request.Request(HEALTH_URL, headers={"User-Agent": "OmniRoute-SelfPinger/1.0"})
        with urllib.request.urlopen(req, context=ctx, timeout=20) as resp:
            ts = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime())
            print(f"[KeepAlive] [{ts}] Self-ping to {HEALTH_URL} -> HTTP {resp.status} OK", flush=True)
    except Exception as e:
        print(f"[KeepAlive] Self-ping warning: {e}", flush=True)

if __name__ == "__main__":
    print(f"[KeepAlive] Self-pinger active for {HEALTH_URL} (every {INTERVAL}s)", flush=True)
    # Wait 20 seconds for server to bind port, then send first test ping
    time.sleep(20)
    ping()
    # Main 9-minute loop
    while True:
        time.sleep(INTERVAL)
        ping()
