#!/bin/bash

# --- CONFIG ---
REMOTE_USER="ubuntu"
REMOTE_HOST="129.153.105.63"  # or IP address
REMOTE_SCRIPT="/home/ubuntu/Decentralized_Saves/upload_alp.sh"
REMOTE_ALP_DIR="/home/ubuntu/Decentralized_Saves/Blockchain Music Saves"
LOCAL_ALP_DIR="/Users/charleskeely/Desktop/Decentralized Saves/Blockchain Music Saves"
SSH_KEY_PATH="/Users/charleskeely/Desktop/Decentralized Saves/ssh-key-2025-02-24.key"

# --- 1) FIND NEWEST .alp LOCALLY ---
cd "$LOCAL_ALP_DIR" || {
  echo "❌ Could not find local directory: $LOCAL_ALP_DIR"
  exit 1
}
latest_file=$(ls -t *.alp 2>/dev/null | head -n 1)
if [[ -z "$latest_file" ]]; then
  echo "❌ No .alp file found locally."
  exit 1
fi

# --- 2) SCP TO ORACLE ---
echo "📤 Copying $latest_file up to Oracle..."
scp -i "$SSH_KEY_PATH" "$latest_file" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_ALP_DIR}/" || {
  echo "❌ scp failed!"
  exit 1
}

# --- 3) TRIGGER ORACLE SCRIPT VIA SSH ---
echo "🚀 Triggering Oracle upload script..."
ssh -i "$SSH_KEY_PATH" "${REMOTE_USER}@${REMOTE_HOST}" "bash '$REMOTE_SCRIPT'"
