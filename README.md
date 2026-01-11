# Decryption Tools

This branch contains only the decryption scripts for the encrypted repository.

## Usage

1. Clone the repository
2. Checkout this branch to get the decrypt script
3. Checkout the encrypted branch
4. Run the decrypt script

```bash
# Get the decrypt tools
git checkout decrypt-tools
cp scripts/decrypt-repo.sh /tmp/

# Go to encrypted branch
git checkout feature/aca-java-build-17099716206204415901
# or
git checkout temp-local-work

# Decrypt
/tmp/decrypt-repo.sh <password>
```

## Encrypted Branches

- `feature/aca-java-build-17099716206204415901` - Main feature branch
- `temp-local-work` - Local work branch

## Note

The `main` branch is NOT encrypted.
