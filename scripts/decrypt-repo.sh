#!/bin/bash
#
# Repository Decryption Script
# Usage: ./decrypt-repo.sh <password>
#
# This script decrypts the encrypted content in the .encrypted/ directory.
# Works for both feature/aca-java-build and temp-local-work branches.
#
set -euo pipefail

PASSWORD="${1:-}"
ENCRYPTED_DIR=".encrypted"

if [[ -z "$PASSWORD" ]]; then
    echo "Usage: $0 <password>"
    echo ""
    echo "Example: $0 'my-secret-password'"
    echo ""
    echo "This will decrypt all files in the .encrypted/ directory."
    exit 1
fi

if [[ ! -d "$ENCRYPTED_DIR" ]]; then
    echo "❌ No encrypted directory found: $ENCRYPTED_DIR"
    echo ""
    echo "Make sure you're on an encrypted branch:"
    echo "  git checkout feature/aca-java-build-17099716206204415901"
    echo "  git checkout temp-local-work"
    exit 1
fi

echo "🔓 Decrypting repository..."
echo ""

# Process each encrypted file
for enc_file in "$ENCRYPTED_DIR"/*.enc; do
    if [[ ! -f "$enc_file" ]]; then
        continue
    fi
    
    filename=$(basename "$enc_file" .enc)
    echo "  Processing: $filename"
    
    # Check if it's a tar archive (directories) or single file
    # Directories don't have extensions in their encrypted name
    if [[ "$filename" == "directories" ]] || [[ "$filename" == "image_evaluation" ]] || [[ "$filename" == "terraform" ]] || [[ "$filename" == "app" ]] || [[ "$filename" == "apps" ]]; then
        # Directory archive - decrypt and extract
        echo "    → Extracting directory archive..."
        openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
            -in "$enc_file" \
            -pass pass:"$PASSWORD" 2>/dev/null | tar -xzf - || {
            echo "❌ Decryption failed for $filename. Wrong password?"
            exit 1
        }
    else
        # Single file - decrypt directly
        echo "    → Decrypting file..."
        openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
            -in "$enc_file" \
            -out "$filename" \
            -pass pass:"$PASSWORD" 2>/dev/null || {
            echo "❌ Decryption failed for $filename. Wrong password?"
            exit 1
        }
    fi
done

echo ""
echo "✅ Decryption complete!"
echo ""
echo "Your files have been restored. You may want to:"
echo "  - Check 'git status' for restored files"
echo "  - NOT commit the decrypted files (they're in .gitignore or were tracked before)"
