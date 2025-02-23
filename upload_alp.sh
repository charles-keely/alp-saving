#!/bin/bash

# Check file permissions on script and working directories
check_permissions() {
    local dirs=(
        "/Users/charleskeely/Desktop/Decentralized Saves"
        "/Users/charleskeely/Desktop/Decentralized Saves/Blockchain Music Saves"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ "$(stat -f %Op "$dir")" != "700" ]]; then
            echo "⚠️ Warning: Directory $dir has loose permissions. Fixing..."
            chmod 700 "$dir"
        fi
    done
    
    # Check script permissions
    if [[ "$(stat -f %Op "$0")" != "700" ]]; then
        echo "⚠️ Warning: Script has loose permissions. Fixing..."
        chmod 700 "$0"
    fi
}

# Check for suspicious file changes
verify_script_integrity() {
    local script_hash
    script_hash=$(shasum -a 256 "$0" | awk '{print $1}')
    
    local hash_file="/Users/charleskeely/Desktop/Decentralized Saves/.script_hash"
    
    if [[ ! -f "$hash_file" ]]; then
        echo "$script_hash" > "$hash_file"
        chmod 600 "$hash_file"
    else
        if [[ "$(cat "$hash_file")" != "$script_hash" ]]; then
            echo "🚨 Warning: Script file has been modified!"
            exit 1
        fi
    fi
}

# Encryption functions
generate_encryption_key() {
    # Generate a secure random password for encryption
    openssl rand -base64 32 > "/Users/charleskeely/Desktop/Decentralized Saves/.encryption_key"
    chmod 600 "/Users/charleskeely/Desktop/Decentralized Saves/.encryption_key"
}

encrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local key_file="/Users/charleskeely/Desktop/Decentralized Saves/.encryption_key"
    
    # Use AES-256-CBC with password-based encryption
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
    local key_file="/Users/charleskeely/Desktop/Decentralized Saves/.encryption_key"
    
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

# Run security checks first
check_permissions
verify_script_integrity

# Ensure encryption key exists
if [[ ! -f "/Users/charleskeely/Desktop/Decentralized Saves/.encryption_key" ]]; then
    echo "🔑 Generating new encryption key..."
    generate_encryption_key
fi

# Clear the error log before running the script
> "/Users/charleskeely/Desktop/Decentralized Saves/script_error.log"

# Redirect errors to log file for debugging
exec 2>> "/Users/charleskeely/Desktop/Decentralized Saves/script_error.log"
set -x

# Ensure w3 is found in Keyboard Maestro
export PATH=$PATH:/opt/homebrew/bin

# Load environment variables from .env file
if [[ -f "/Users/charleskeely/Desktop/Decentralized Saves/.env" ]]; then
    export $(grep -v '^#' "/Users/charleskeely/Desktop/Decentralized Saves/.env" | xargs)
else
    echo "❌ .env file not found!"
    exit 1
fi

# Check if web3key is loaded
if [[ -z "$web3key" ]]; then
    echo "❌ web3key is not set in the .env file!"
    exit 1
fi

# Navigate to the directory containing your .alp files
cd "/Users/charleskeely/Desktop/Decentralized Saves/Blockchain Music Saves/" || { echo "❌ Directory not found!"; exit 1; }

# Find the most recent .alp file
latest_file=$(ls -t *.alp | head -n 1)

# Space Key for "ableton-alp-files"
SPACE_KEY="$web3key"

# Log files
LOG_FILE="/Users/charleskeely/Desktop/Decentralized Saves/upload_log.txt"
HASH_LOG="/Users/charleskeely/Desktop/Decentralized Saves/file_hashes.log"

# GitHub repository details
GITHUB_REPO="git@github.com:charles-keely/alp-hashes.git"
GITHUB_DIR="/Users/charleskeely/Desktop/Decentralized Saves/alp-hashes"

# Function to get file size in bytes
get_file_size() {
    stat -f %z "$1"
}

# Function to sync hash log with GitHub
sync_with_github() {
    # Check if GitHub directory exists
    if [ ! -d "$GITHUB_DIR" ]; then
        echo "📦 Cloning GitHub repository..."
        git clone "$GITHUB_REPO" "$GITHUB_DIR"
    fi

    # Copy the updated hash log to GitHub directory
    cp "$HASH_LOG" "$GITHUB_DIR/file_hashes.log"

    # Navigate to GitHub directory
    cd "$GITHUB_DIR" || { echo "❌ Failed to navigate to GitHub directory!"; exit 1; }

    # Add, commit, and push changes
    git add file_hashes.log
    git commit -m "Update file hashes: $(date '+%Y-%m-%d %H:%M:%S')"
    git push origin main

    echo "✅ Successfully synced hash log with GitHub"

    # Return to original directory
    cd - || { echo "❌ Failed to return to original directory!"; exit 1; }
}

if [[ -n "$latest_file" ]]; then
    project_name=$(basename "$latest_file" .alp)
    
    # Get original file size and hash
    original_size=$(get_file_size "$latest_file")
    original_hash=$(shasum -a 256 "$latest_file" | awk '{print $1}')
    
    echo "📊 Original file size: $original_size bytes"
    echo "🔑 Original file hash: $original_hash"

    # Calculate version number and log hash first
    version=1
    while [[ -f "${project_name}_v${version}.alp" ]] || grep -q "${project_name}_v${version}.alp" "$LOG_FILE"; do
        ((version++))
    done
    versioned_name="${project_name}_v${version}.alp"
    
    # Log hash information first
    echo "$(date '+%Y-%m-%d %H:%M:%S') | Original: $latest_file | Versioned: $versioned_name | Hash: $original_hash | Size: $original_size bytes" >> "$HASH_LOG"

    # Sync with GitHub early
    sync_with_github

    # Create the versioned file
    cp "$latest_file" "$versioned_name"
    
    # Create encrypted version
    encrypted_name="${versioned_name}.enc"
    echo "🔒 Encrypting file..."
    
    if ! encrypt_file "$versioned_name" "$encrypted_name"; then
        echo "❌ Encryption failed!"
        rm -f "$versioned_name"
        exit 1
    fi
    
    echo "📂 Uploading encrypted file to Web3.Storage..."
    
    # Upload encrypted file and capture full output
    upload_output=$(/opt/homebrew/bin/w3 up --no-wrap "$encrypted_name" 2>&1)
    
    # Check if upload was successful
    if [[ $? -ne 0 ]]; then
        echo "❌ Upload failed with error:"
        echo "$upload_output"
        rm -f "$versioned_name" "$encrypted_name"
        exit 1
    fi

    # Extract CID
    cid=$(echo "$upload_output" | grep 'https://w3s.link/ipfs/' | sed 's|.*/||')
    
    if [[ -n "$cid" ]]; then
        echo "✅ Upload successful! CID: $cid"
        
        # Store both CID and w3s.link URL in log
        echo "$versioned_name https://w3s.link/ipfs/$cid" >> "$LOG_FILE"
        
        # Verify the uploaded file
        echo "📥 Verifying uploaded file..."
        temp_dir="/tmp/alp_verify"
        mkdir -p "$temp_dir"
        temp_encrypted_file="${temp_dir}/${encrypted_name}"
        temp_decrypted_file="${temp_dir}/${versioned_name}"
        
        # Try both w3 get with CID and direct download as fallback
        if /opt/homebrew/bin/w3 get "$cid" > "$temp_encrypted_file" 2>/dev/null || \
           curl -L --max-time 60 --retry 3 --retry-delay 10 \
           -H "Accept: application/octet-stream" \
           "https://w3s.link/ipfs/$cid" > "$temp_encrypted_file"; then
            
            # Decrypt and verify the downloaded file
            if decrypt_file "$temp_encrypted_file" "$temp_decrypted_file"; then
                # Verify decrypted file
                downloaded_hash=$(shasum -a 256 "$temp_decrypted_file" | awk '{print $1}')
                
                echo "📊 Downloaded file size: $(get_file_size "$temp_decrypted_file") bytes"
                echo "🔑 Downloaded file hash: $downloaded_hash"
                
                if [[ "$original_size" == "$(get_file_size "$temp_decrypted_file")" ]]; then
                    if [[ "$original_hash" == "$downloaded_hash" ]]; then
                        echo "✅ File verified successfully!"
                    else
                        echo "❌ Hash verification failed!"
                        echo "Original hash: $original_hash"
                        echo "Downloaded hash: $downloaded_hash"
                        exit 1
                    fi
                else
                    echo "❌ Size mismatch!"
                    echo "Original size: $original_size bytes"
                    echo "Downloaded size: $(get_file_size "$temp_decrypted_file") bytes"
                    exit 1
                fi
            else
                echo "❌ Decryption verification failed!"
                exit 1
            fi
        else
            echo "❌ Failed to retrieve file!"
            exit 1
        fi
        
        # Cleanup
        rm -f "$versioned_name" "$encrypted_name"
        rm -rf "$temp_dir"
    else
        echo "❌ Failed to extract CID from upload output!"
        echo "Upload output was:"
        echo "$upload_output"
        rm -f "$versioned_name" "$encrypted_name"
        exit 1
    fi
else
    echo "❌ No .alp files found."
    exit 1
fi