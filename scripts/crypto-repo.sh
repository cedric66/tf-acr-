#!/bin/bash
#
# Repository Encryption Script
# Usage: ./encrypt-repo.sh [encrypt|decrypt] <password>
#
set -euo pipefail

ACTION="${1:-}"
PASSWORD="${2:-}"

# Directories/files to encrypt (including README.md)
SENSITIVE_PATHS=(
    "image_evaluation"
    "terraform"
    "app"
    "apps"
    "README.md"
    "AZURE_DEPLOYMENT_GUIDE.md"
    "TERRAFORM_REVIEW_SUMMARY.md"
    "azure_implementation_plan.md"
    "terraform_review_issues.md"
)

# Note: scripts/ folder kept for decrypt capability
# LICENSE and .gitignore kept for repo structure

ENCRYPTED_DIR=".encrypted"

usage() {
    echo "Usage: $0 [encrypt|decrypt] <password>"
    echo ""
    echo "Commands:"
    echo "  encrypt  - Encrypt sensitive directories"
    echo "  decrypt  - Decrypt sensitive directories"
    echo ""
    echo "Example:"
    echo "  $0 encrypt 'my-secret-password'"
    echo "  $0 decrypt 'my-secret-password'"
    exit 1
}

encrypt_repo() {
    local pass="$1"
    
    echo "🔐 Encrypting repository..."
    
    # Create encrypted directory
    mkdir -p "$ENCRYPTED_DIR"
    
    for path in "${SENSITIVE_PATHS[@]}"; do
        if [[ -e "$path" ]]; then
            echo "  Encrypting: $path"
            
            # Create encrypted archive
            tar -czf - "$path" 2>/dev/null | \
                openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
                -out "$ENCRYPTED_DIR/${path//\//_}.enc" \
                -pass pass:"$pass"
            
            # Remove original (move to backup first)
            rm -rf "$path"
        fi
    done
    
    # Create marker file
    echo "This repository contains encrypted content." > "$ENCRYPTED_DIR/README.md"
    echo "Use './decrypt-repo.sh <password>' to decrypt." >> "$ENCRYPTED_DIR/README.md"
    echo "" >> "$ENCRYPTED_DIR/README.md"
    echo "Encrypted on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$ENCRYPTED_DIR/README.md"
    
    echo ""
    echo "✅ Encryption complete!"
    echo ""
    echo "Encrypted files are in: $ENCRYPTED_DIR/"
    echo "Original directories have been removed."
    echo ""
    echo "⚠️  IMPORTANT: Remember your password! There is no recovery."
    echo ""
    echo "To decrypt: ./scripts/decrypt-repo.sh <password>"
}

decrypt_repo() {
    local pass="$1"
    
    echo "🔓 Decrypting repository..."
    
    if [[ ! -d "$ENCRYPTED_DIR" ]]; then
        echo "❌ No encrypted directory found: $ENCRYPTED_DIR"
        exit 1
    fi
    
    for enc_file in "$ENCRYPTED_DIR"/*.enc; do
        if [[ -f "$enc_file" ]]; then
            echo "  Decrypting: $(basename "$enc_file")"
            
            # Decrypt and extract
            openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
                -in "$enc_file" \
                -pass pass:"$pass" 2>/dev/null | tar -xzf - || {
                echo "❌ Decryption failed. Wrong password?"
                exit 1
            }
        fi
    done
    
    echo ""
    echo "✅ Decryption complete!"
    echo ""
    echo "Your files have been restored."
}

# Main
if [[ -z "$ACTION" ]] || [[ -z "$PASSWORD" ]]; then
    usage
fi

case "$ACTION" in
    encrypt)
        encrypt_repo "$PASSWORD"
        ;;
    decrypt)
        decrypt_repo "$PASSWORD"
        ;;
    *)
        usage
        ;;
esac
