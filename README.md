# Azure Developer VM & Image Hardening Lab

This project provides a Terraform-based solution to deploy a feature-rich, secure, and automated **Developer Virtual Machine** in Azure. It is designed for DevOps engineers working with Kubernetes, Container Security, and Image Hardening.

## Key Features

### 🏗 Infrastructure
-   **Secure by Default**: Private IP only (no Public IP), attached to existing or new VNet.
-   **Cost Efficient**: Support for **Spot Instances** (`enable_spot`) and configurable VM SKUs (`vm_size`).
-   **Automated Scheduling**:
    -   **Auto-Shutdown**: 7:00 PM daily.
    -   **Auto-Startup**: 8:15 AM (Mon-Fri) via Azure Automation.
-   **Persistence**: Boot Diagnostics enabled for Serial Console access.

### 🛠 Tooling
Pre-loaded with a comprehensive DevSecOps toolkit:
-   **Containerization**: Docker, Azure CLI, `crane`, `skopeo`, `cosign`.
-   **Kubernetes**: `kubectl`, `helm`, `k9s`, `kubectx`, `kubens`, `kustomize`.
-   **Security Scanning**: `Trivy`, `Grype`, `Syft` (SBOM).
-   **Productivity**: `gh` (GitHub CLI), `jq`, `yq`, `fzf`, `htop`, `ncdu`, `tree`.
-   **Python**: Python 3, `pip`, `venv`.

### 🛡 Security & Automation
-   **Managed Identity**: System Assigned Identity with `Contributor` access for self-management.
-   **Cloud Drive**: Auto-mounts Azure File Share to `~/clouddrive`.
-   **Protection**: Auto-updating `CreationDate` tag to prevent automated cleanup scripts from deleting the VM.
-   **Health & Maintenance**:
    -   Weekly Docker Prune.
    -   Daily Trivy/Grype DB updates.
    -   Disk usage alerts (>80%) broadcast to logged-in users.

## Quick Start

1.  **Add SSH Keys**: Place public keys in `keys/`.
2.  **Configure**: Set variables in `terraform/environments/dev/terraform.tfvars`.
3.  **Deploy**: Run `terraform apply`.

See the [Deployment Guide](terraform/environments/dev/README.md) for detailed instructions.