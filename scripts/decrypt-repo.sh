#!/bin/bash
#
# Repository Decryption Script
# Usage: ./decrypt-repo.sh <password>
#
set -euo pipefail

PASSWORD="${1:-}"
ENCRYPTED_DIR=".encrypted"

if [[ -z "$PASSWORD" ]]; then
    echo "Usage: $0 <password>"
    echo ""
    echo "Example: $0 'my-secret-password'"
    exit 1
fi

if [[ ! -d "$ENCRYPTED_DIR" ]]; then
    echo "❌ No encrypted directory found: $ENCRYPTED_DIR"
    exit 1
fi

echo "🔓 Decrypting repository..."

# Decrypt directories (tar archives)
for enc_file in "$ENCRYPTED_DIR"/*.enc; do
    filename=$(basename "$enc_file" .enc)
    
    # Check if it's a tar archive (directories) or single file
    if [[ "$filename" == *".md" ]]; then
        # Single file - decrypt directly
        echo "  Decrypting: $filename"
        openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
            -in "$enc_file" \
            -out "$filename" \
            -pass pass:"$PASSWORD" 2>/dev/null || {
            echo "❌ Decryption failed for $filename. Wrong password?"
            exit 1
        }
    else
        # Directory - decrypt and extract tar
        echo "  Decrypting: $filename/"
        openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
            -in "$enc_file" \
            -pass pass:"$PASSWORD" 2>/dev/null | tar -xzf - || {
            echo "❌ Decryption failed for $filename. Wrong password?"
            exit 1
        }
    fi
done

echo ""
echo "✅ Decryption complete!"
echo ""
echo "Your files have been restored."
