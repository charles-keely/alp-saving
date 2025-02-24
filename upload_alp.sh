#!/bin/bash

# ------------------------------------------------
# Single timestamp for ALL logs in this run
# ------------------------------------------------
GLOBAL_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ------------------------------------------------
# 1) SECURITY CHECKS
# ------------------------------------------------

check_permissions() {
    # Directories we want to enforce 700 perms on
    local dirs=(
        "/home/ubuntu/Decentralized_Saves"
        "/home/ubuntu/Decentralized_Saves/Blockchain Music Saves"
    )
    for dir in "${dirs[@]}"; do
        # On Linux, stat -c %a gives the octal perms
        local actual_perm
        actual_perm=$(stat -c %a "$dir" 2>/dev/null) || {
            echo "❌ Directory $dir not found!"
            exit 1
        }
        if [[ "$actual_perm" != "700" ]]; then
            echo "⚠️  Warning: Directory $dir has loose permissions. Fixing..."
            chmod 700 "$dir"
        fi
    done
    
    # Check script permissions
    local script_perm
    script_perm=$(stat -c %a "$0")
    if [[ "$script_perm" != "700" ]]; then
        echo "⚠️  Warning: Script has loose permissions. Fixing..."
        chmod 700 "$0"
    fi
}

verify_script_integrity() {
    # Compare current script's hash to .script_hash
    local script_hash
    script_hash=$(sha256sum "$0" | awk '{print $1}')
    
    local hash_file="/home/ubuntu/Decentralized_Saves/.script_hash"
    
    if [[ ! -f "$hash_file" ]]; then
        # First run (or no .script_hash yet), create it
        echo "$script_hash" > "$hash_file"
        chmod 600 "$hash_file"
    else
        # Compare stored hash to current
        if [[ "$(cat "$hash_file")" != "$script_hash" ]]; then
            echo "🚨 Warning: Script file has been modified illegally!"
            exit 1
        fi
    fi
    
    # Log the script hash w/ global timestamp
    echo "$GLOBAL_TIMESTAMP | Script Hash: $script_hash" >> "/home/ubuntu/Decentralized_Saves/script_hashes.log"
}

# Encryption functions
generate_encryption_key() {
    openssl rand -base64 32 > "/home/ubuntu/Decentralized_Saves/.encryption_key"
    chmod 600 "/home/ubuntu/Decentralized_Saves/.encryption_key"
}

encrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local key_file="/home/ubuntu/Decentralized_Saves/.encryption_key"

    openssl enc -aes-256-cbc -salt \
        -in "$input_file" \
        -out "$output_file" \
        -pass file:"$key_file" \
        -pbkdf2 \
        -iter 100000 || {
            echo "❌ Encryption failed!"
            return 1
        }
    return 0
}

decrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local key_file="/home/ubuntu/Decentralized_Saves/.encryption_key"
    # Decrypt using the same parameters
    openssl enc -aes-256-cbc -d -salt \
        -in "$input_file" \
        -out "$output_file" \
        -pass file:"$key_file" \
        -pbkdf2 \
        -iter 100000 || {
            echo "❌ Decryption failed!"
            return 1
        }
    return 0
}

# ------------------------------------------------
# 2) GITHUB LOG SYNC FUNCTION
# ------------------------------------------------

sync_with_github() {
    # If local GitHub clone doesn't exist, clone it
    if [[ ! -d "$GITHUB_DIR" ]]; then
        echo "📦 Cloning GitHub repository..."
        git clone "$GITHUB_REPO" "$GITHUB_DIR"
    fi
    
    # Copy logs into that repo
    cp "$HASH_LOG" "$GITHUB_DIR/file_hashes.log"
    cp "/home/ubuntu/Decentralized_Saves/script_hashes.log" "$GITHUB_DIR/script_hashes.log"
    cp "/home/ubuntu/Decentralized_Saves/cid_log.txt" "$GITHUB_DIR/cid_log.txt"

    # Commit and push
    cd "$GITHUB_DIR" || { echo "❌ Failed to enter $GITHUB_DIR"; exit 1; }
    git add file_hashes.log script_hashes.log cid_log.txt
    git commit -m "Update hashes: $GLOBAL_TIMESTAMP"
    git push origin main
    cd - >/dev/null 2>&1

    echo "✅ Successfully synced hash logs with GitHub."
}

# ------------------------------------------------
# SCRIPT EXECUTION BEGINS
# ------------------------------------------------

# 1) Basic security checks & script integrity
check_permissions
verify_script_integrity

# 2) Ensure we have an encryption key
if [[ ! -f "/home/ubuntu/Decentralized_Saves/.encryption_key" ]]; then
    echo "🔑 Generating new encryption key..."
    generate_encryption_key
fi

# 3) Clear & start logging errors
> "/home/ubuntu/Decentralized_Saves/script_error.log"
exec 2>> "/home/ubuntu/Decentralized_Saves/script_error.log"
set -x

# 4) Load .env
if [[ -f "/home/ubuntu/Decentralized_Saves/.env" ]]; then
    export $(grep -v '^#' "/home/ubuntu/Decentralized_Saves/.env" | xargs)
else
    echo "❌ .env file not found!"
    exit 1
fi

if [[ -z "$web3key" ]]; then
    echo "❌ web3key is not set in the .env file!"
    exit 1
fi

echo "web3key: $web3key"

# 5) cd to the directory with .alp files on Oracle
cd "/home/ubuntu/Decentralized_Saves/Blockchain Music Saves/" || {
    echo "❌ Directory not found!"
    exit 1
}

# 6) Identify newest .alp
latest_file=$(ls -t *.alp 2>/dev/null | head -n 1)
if [[ -z "$latest_file" ]]; then
    echo "❌ No .alp files found."
    exit 1
fi

# Some global definitions
LOG_FILE="/home/ubuntu/Decentralized_Saves/upload_log.txt"
HASH_LOG="/home/ubuntu/Decentralized_Saves/file_hashes.log"
GITHUB_REPO="git@github.com:charles-keely/alp-hashes.git"
GITHUB_DIR="/home/ubuntu/Decentralized_Saves/alp-hashes"

# Helper to get file size
get_file_size() {
    stat -c %s "$1"
}

# ------------------------------------------------
# 7) PROCESS & VERSION THE FILE
# ------------------------------------------------

project_name=$(basename "$latest_file" .alp)
original_size=$(get_file_size "$latest_file")
original_hash=$(sha256sum "$latest_file" | awk '{print $1}')

echo "📊 Original file size: $original_size bytes"
echo "🔑 Original file hash: $original_hash"

# Find next version number
version=1
while [[ -f "${project_name}_v${version}.alp" ]] || grep -q "${project_name}_v${version}.alp" "$LOG_FILE"; do
    ((version++))
done
versioned_name="${project_name}_v${version}.alp"

# Log it
echo "$GLOBAL_TIMESTAMP | Original: $latest_file | Versioned: $versioned_name | Hash: $original_hash | Size: $original_size bytes" >> "$HASH_LOG"

# Copy to a versioned name
cp "$latest_file" "$versioned_name"

# ------------------------------------------------
# 8) ENCRYPT AND UPLOAD
# ------------------------------------------------

encrypted_name="${versioned_name}.enc"
echo "🔒 Encrypting file..."
if ! encrypt_file "$versioned_name" "$encrypted_name"; then
    echo "❌ Encryption failed."
    rm -f "$versioned_name"
    exit 1
fi

# Note: adjust path to `w3` if needed (e.g. /usr/bin/w3, /usr/local/bin/w3, etc.)
W3_CLI="/usr/bin/w3"

echo "📂 Uploading encrypted file to Web3.Storage..."
upload_output=$($W3_CLI up --no-wrap "$encrypted_name" 2>&1)
if [[ $? -ne 0 ]]; then
    echo "❌ Upload failed with error:"
    echo "$upload_output"
    rm -f "$versioned_name" "$encrypted_name"
    exit 1
fi

# Attempt to parse the CID
cid=$(echo "$upload_output" | grep 'https://w3s.link/ipfs/' | sed 's|.*/||')
if [[ -z "$cid" ]]; then
    echo "❌ Failed to extract CID from upload output!"
    echo "$upload_output"
    rm -f "$versioned_name" "$encrypted_name"
    exit 1
fi

echo "✅ Upload successful! CID: $cid"

# Log it
echo "$GLOBAL_TIMESTAMP | File: $versioned_name | CID: $cid" >> "/home/ubuntu/Decentralized_Saves/cid_log.txt"
echo "$versioned_name https://w3s.link/ipfs/$cid" >> "$LOG_FILE"

# ------------------------------------------------
# 9) VERIFICATION STEP
# ------------------------------------------------

echo "📥 Verifying uploaded file..."
temp_dir="/tmp/alp_verify"
mkdir -p "$temp_dir"
temp_encrypted_file="${temp_dir}/${encrypted_name}"
temp_decrypted_file="${temp_dir}/${versioned_name}"

# Try retrieving the file: first w3 get, or fallback to curl
if $W3_CLI get "$cid" > "$temp_encrypted_file" 2>/dev/null || \
   curl -L --max-time 60 --retry 3 --retry-delay 10 -H "Accept: application/octet-stream" \
   "https://w3s.link/ipfs/$cid" > "$temp_encrypted_file"; then
    
    if decrypt_file "$temp_encrypted_file" "$temp_decrypted_file"; then
        downloaded_hash=$(sha256sum "$temp_decrypted_file" | awk '{print $1}')
        downloaded_size=$(get_file_size "$temp_decrypted_file")

        echo "📊 Downloaded file size: $downloaded_size bytes"
        echo "🔑 Downloaded file hash: $downloaded_hash"
        
        if [[ "$downloaded_size" == "$original_size" && "$downloaded_hash" == "$original_hash" ]]; then
            echo "✅ File verified successfully!"
        else
            echo "❌ Verification mismatch!"
            echo "Original size/hash: $original_size / $original_hash"
            echo "Downloaded size/hash: $downloaded_size / $downloaded_hash"
            rm -rf "$temp_dir" "$versioned_name" "$encrypted_name"
            exit 1
        fi
    else
        echo "❌ Decryption failed during verification!"
        rm -rf "$temp_dir" "$versioned_name" "$encrypted_name"
        exit 1
    fi
else
    echo "❌ Failed to retrieve file from IPFS!"
    rm -rf "$temp_dir" "$versioned_name" "$encrypted_name"
    exit 1
fi

# Cleanup temporary & local copy
rm -f "$versioned_name" "$encrypted_name"
rm -rf "$temp_dir"

# Also remove the original .alp to save space
rm -f "$latest_file"

# ------------------------------------------------
# 10) SYNC LOGS TO GITHUB
# ------------------------------------------------

sync_with_github

echo "✅ Done! The file has been safely uploaded and verified."
exit 0
