#!/bin/bash

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

# Function to get file size in bytes
get_file_size() {
    stat -f %z "$1"
}

if [[ -n "$latest_file" ]]; then
    project_name=$(basename "$latest_file" .alp)
    
    # Get original file size and hash
    original_size=$(get_file_size "$latest_file")
    original_hash=$(shasum -a 256 "$latest_file" | awk '{print $1}')
    
    echo "📊 Original file size: $original_size bytes"
    echo "🔑 Original file hash: $original_hash"
    echo "$latest_file $original_hash $original_size" >> "$HASH_LOG"

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
