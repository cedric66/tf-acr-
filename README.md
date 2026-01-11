# Encrypted Repository

This repository contains encrypted content.

## How to Decrypt

The decryption script is in the `decrypt-tools` branch:

```bash
# Get the decrypt script
git checkout decrypt-tools
cp scripts/decrypt-repo.sh /tmp/

# Return to this branch
git checkout feature/aca-java-build-17099716206204415901

# Decrypt
/tmp/decrypt-repo.sh <password>
```

## Encrypted Contents

- `image_evaluation/` - Container image evaluation results
- `terraform/` - Infrastructure as Code
- `app/` - Application code
- `apps/` - Additional applications
- Documentation files (*.md)

## Contact

For access, contact the repository owner.

---
*Encrypted on: 2026-01-12*
