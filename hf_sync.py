"""
Hugging Face Dataset Auto-Sync for OmniRoute SQLite Database.
Handles automated download on container start and safe hot-backups to a private HF Dataset.
"""

import os
import sys
import time
import shutil
import sqlite3
from typing import Optional

# Configuration paths and environment variables
DATA_DIR: str = os.getenv("DATA_DIR", "/app/data")
DB_PATH: str = os.path.join(DATA_DIR, "storage.sqlite")
BACKUP_PATH: str = "/tmp/storage_backup.sqlite"
HF_TOKEN: Optional[str] = os.getenv("HF_TOKEN")
DATASET_ID: Optional[str] = os.getenv("HF_DATASET_ID")  # Format: "username/omniroute-storage"

# Lazy-loaded Hugging Face API client
_api = None


def get_hf_api():
    """Initialize and return the Hugging Face API client if HF_TOKEN is configured."""
    global _api
    if _api is None and HF_TOKEN:
        try:
            from huggingface_hub import HfApi
            _api = HfApi(token=HF_TOKEN)
        except ImportError:
            print("[HF Sync Error] huggingface_hub package is not installed.", flush=True)
            return None
    return _api


def ensure_private_dataset() -> bool:
    """Ensure the target private Hugging Face Dataset exists, creating it if necessary."""
    api = get_hf_api()
    if not api or not DATASET_ID:
        return False

    try:
        api.create_repo(
            repo_id=DATASET_ID,
            repo_type="dataset",
            private=True,
            exist_ok=True,
        )
        return True
    except Exception as err:
        print(f"[HF Sync] Warning while verifying dataset repo: {err}", flush=True)
        return False


def download_database() -> None:
    """Download storage.sqlite from the private HF dataset on container startup."""
    api = get_hf_api()
    if not api or not DATASET_ID:
        print("[HF Sync] HF_TOKEN or HF_DATASET_ID not configured. Skipping dataset download.", flush=True)
        return

    ensure_private_dataset()
    print(f"[HF Sync] Checking for existing storage.sqlite in dataset '{DATASET_ID}'...", flush=True)

    try:
        from huggingface_hub import hf_hub_download
        from huggingface_hub.utils import EntryNotFoundError

        downloaded_file = hf_hub_download(
            repo_id=DATASET_ID,
            filename="storage.sqlite",
            repo_type="dataset",
            token=HF_TOKEN,
        )

        os.makedirs(DATA_DIR, exist_ok=True)
        shutil.copy2(downloaded_file, DB_PATH)
        print(f"[HF Sync] Successfully restored database to {DB_PATH}", flush=True)

    except EntryNotFoundError:
        print("[HF Sync] No previous database found in dataset. Starting with a fresh database.", flush=True)
    except Exception as err:
        print(f"[HF Sync] Download skipped or encountered an error: {err}", flush=True)


def upload_database() -> None:
    """Create a safe hot-backup of storage.sqlite and upload to the private HF dataset."""
    api = get_hf_api()
    if not api or not DATASET_ID:
        return

    if not os.path.exists(DB_PATH):
        print("[HF Sync] storage.sqlite does not exist yet. Skipping backup.", flush=True)
        return

    try:
        # Use SQLite's online backup API to avoid database locks or corruption
        src_conn = sqlite3.connect(DB_PATH)
        dst_conn = sqlite3.connect(BACKUP_PATH)
        src_conn.backup(dst_conn)
        dst_conn.close()
        src_conn.close()

        # Upload hot backup to the private Hugging Face Dataset
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime())
        api.upload_file(
            path_or_fileobj=BACKUP_PATH,
            path_in_repo="storage.sqlite",
            repo_id=DATASET_ID,
            repo_type="dataset",
            commit_message=f"Automated OmniRoute backup [{timestamp}]",
        )
        print(f"[HF Sync] Successfully backed up database to dataset '{DATASET_ID}' at {timestamp}", flush=True)

    except Exception as err:
        print(f"[HF Sync] Error during database backup/upload: {err}", flush=True)
    finally:
        if os.path.exists(BACKUP_PATH):
            try:
                os.remove(BACKUP_PATH)
            except OSError:
                pass


def run_sync_loop() -> None:
    """Background loop that periodically uploads database backups to the HF dataset."""
    # Default sync interval is 15 minutes (900 seconds)
    interval_sec = int(os.getenv("HF_SYNC_INTERVAL_SEC", "900"))
    print(f"[HF Sync Loop] Periodic sync started (runs every {interval_sec} seconds).", flush=True)

    while True:
        time.sleep(interval_sec)
        upload_database()


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "download"
    if action == "download":
        download_database()
    elif action == "upload":
        upload_database()
    elif action == "loop":
        run_sync_loop()
    else:
        print(f"Unknown action: {action}. Use 'download', 'upload', or 'loop'.", file=sys.stderr)
        sys.exit(1)

