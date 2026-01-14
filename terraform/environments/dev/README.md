# Dev Environment Deployment Guide

This directory contains the Terraform configuration to deploy the **Azure Developer VM**.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Terraform](https://www.terraform.io/downloads.html)
- Azure Subscription access

## Configuration

### 1. SSH Keys
Place the public SSH keys for the two default users (`sk` and `vk`) in the project root:
-   `keys/sk.pub`
-   `keys/vk.pub`

*(Paths can be customized in `variables.tf`)*

### 2. Terraform Variables
Create a `terraform.tfvars` file in this directory. Use `terraform.tfvars.example` as a template.

**Key Variables:**

| Variable | Description | Default |
|----------|-------------|---------|
| `subnet_id` | **Required** for private access. If null, a NEW VNet is created. | `null` |
| `enable_spot` | Set to `true` for significant cost savings (evictable). | `false` |
| `vm_size` | VM SKU (e.g., `Standard_B2s`, `Standard_D4s_v3`). | `Standard_B2s` |
| `enable_auto_start`| Start VM at 8:15 AM (Mon-Fri). | `true` |
| `tags` | Map of tags to merge with defaults. | `{}` |

**Cloud Drive Config:**
You must provide `storage_account_name`, `storage_account_rg`, and `file_share_name` to enable the auto-mount feature.

## Deployment

```bash
# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply
```

## Accessing the VM

The VM does **NOT** have a Public IP. You must access it via one of the following methods:

1.  **VPN / ExpressRoute**: If you are on the corporate network.
2.  **Bastion Host**: Jump from another VM in the same VNet.
3.  **Azure Serial Console**: Available in the Azure Portal (Boot Diagnostics is enabled).

**SSH Command:**
```bash
ssh -i ~/.ssh/your_key sk@<PRIVATE_IP>
```
*(The Private IP is outputted by Terraform as `vm_private_ip`)*

## Post-Deployment Features

### ☁️ Cloud Drive
Your Azure File Share is mounted at:
```bash
/home/sk/clouddrive
/home/vk/clouddrive
```

### 🤖 Maintenance & Cron Jobs
The VM manages itself via `cloud-init` configured cron jobs (logs in `/var/log/`):

-   **00:00 Daily**: Updates `CreationDate` tag (Self-Protection).
-   **02:00 Sunday**: `docker system prune -af` (Disk cleanup).
-   **06:00 Daily**: `trivy` and `grype` DB updates.
-   **Every 30m**: Checks/Remounts Cloud Drive.
-   **07:00 Daily**: Disk Usage Check (Alerts via `wall` if >80%).

### 🖥 Custom Shell
The shell prompt is enhanced to show:
-   Current Git Branch
-   Active Azure Subscription
-   Current Kubernetes Context

### 📋 Helper Scripts
Located in `/usr/local/bin/`:
-   `list-subscriptions`: Show all Azure subs.
-   `list-aks-clusters`: Find all AKS clusters across subs.
-   `get-aks-details <name> <rg>`: Dump Network/Identity/NodePool info for a cluster.
