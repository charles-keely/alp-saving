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

# Run security checks first
check_permissions
verify_script_integrity

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
    # Log both original and versioned filename with the hash
    # Calculate version number first
    version=1
    while [[ -f "${project_name}_v${version}.alp" ]] || grep -q "${project_name}_v${version}.alp" "$LOG_FILE"; do
        ((version++))
    done
    versioned_name="${project_name}_v${version}.alp"
    
    # Log with correct version number
    echo "$(date '+%Y-%m-%d %H:%M:%S') | Original: $latest_file | Versioned: $versioned_name | Hash: $original_hash | Size: $original_size bytes" >> "$HASH_LOG"

    # Sync updated hash log with GitHub
    sync_with_github

    # Version handling - simplified
    version=1
    while [[ -f "${project_name}_v${version}.alp" ]] || grep -q "${project_name}_v${version}.alp" "$LOG_FILE"; do
        ((version++))
    done
    versioned_name="${project_name}_v${version}.alp"

    # Create a copy with versioned name
    cp "$latest_file" "$versioned_name"

    echo "📂 Uploading $versioned_name to Web3.Storage..."

    # Upload and capture full output
    upload_output=$(/opt/homebrew/bin/w3 up --no-wrap "$versioned_name" 2>&1)
    
    # Check if upload was successful
    if [[ $? -ne 0 ]]; then
        echo "❌ Upload failed with error:"
        echo "$upload_output"
        exit 1
    fi

    # Extract CID - using the full URL and then extracting the last part
    cid=$(echo "$upload_output" | grep 'https://w3s.link/ipfs/' | sed 's|.*/||')
    
    if [[ -n "$cid" ]]; then
        echo "✅ Upload successful! CID: $cid"
        
        # Store both CID and w3s.link URL in log
        echo "$versioned_name https://w3s.link/ipfs/$cid" >> "$LOG_FILE"
        
        # Try to retrieve using w3 get
        echo "📥 Attempting to retrieve file using w3 get..."
        temp_dir="/tmp/alp_verify"
        mkdir -p "$temp_dir"
        temp_downloaded_file="${temp_dir}/${versioned_name}"
        
        # Try both w3 get with CID and direct download as fallback
        if /opt/homebrew/bin/w3 get "$cid" > "$temp_downloaded_file" 2>/dev/null || \
           curl -L --max-time 60 --retry 3 --retry-delay 10 \
           -H "Accept: application/octet-stream" \
           "https://w3s.link/ipfs/$cid" > "$temp_downloaded_file"; then
            
            # Verify downloaded file
            downloaded_size=$(get_file_size "$temp_downloaded_file")
            downloaded_hash=$(shasum -a 256 "$temp_downloaded_file" | awk '{print $1}')
            
            echo "📊 Downloaded file size: $downloaded_size bytes"
            echo "🔑 Downloaded file hash: $downloaded_hash"
            
            if [[ "$original_size" == "$downloaded_size" ]]; then
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
                echo "Downloaded size: $downloaded_size bytes"
                exit 1
            fi
        else
            echo "❌ Failed to retrieve file!"
            exit 1
        fi
        
        # Cleanup
        rm -f "$versioned_name"
        rm -rf "$temp_dir"
    else
        echo "❌ Failed to extract CID from upload output!"
        echo "Upload output was:"
        echo "$upload_output"
        exit 1
    fi
else
    echo "❌ No .alp files found."
    exit 1
fi