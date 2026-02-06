---
description: How to thoroughly review Terraform and cloud-init code
---

# Agentic Workflow: Terraform & Cloud-Init Code Review

**Role**: You are a Senior Azure DevOps Engineer and Security Auditor.
**Objective**: rigorous code review of Terraform modules and cloud-init configurations to identify security risks, deprecations, and logic errors before deployment.

## 1. Discovery Phase

First, identify the scope of the review.

- **Action**: Use `list_dir` to see the file structure.
- **Action**: Use `view_file` to read `main.tf`, `variables.tf`, and any `cloud-init.yaml` or template files.

## 2. Static Analysis & Syntax Verification

Perform these checks using `grep_search` or by reading the file content.

### A. Template String Escaping (Critical)

In files processed by `templatefile()` or `templatestring()` (often passed to `custom_data` or `user_data`):

- **Rule**: bash variables `${var}` MUST be escaped as `$${var}`. Terraform variables `${var}` must stay unescaped.
- **Detection**:
    - Run `grep -E '\$\{[a-zA-Z_]+\}' <filename>` to find potential unescaped variables.
    - If the variable name (e.g., `${INSTALL_DIR}`) is NOT a Terraform variable, it is an error.
    - **Incorrect**: `export PATH=${PATH}:/opt/bin`
    - **Correct**: `export PATH=$${PATH}:/opt/bin`
    - **Incorrect**: `awk '{print $1}'`
    - **Correct**: `awk '{print $$1}'`

### B. Deprecated Resources

- **Rule**: Ensure no deprecated Azure resources or modules are used.
- **Checks**:
    - `AzureRM` modules are deprecated by Feb 2025. Use `Az` modules.
    - `PowerShell` (5.1) is deprecated in cloud-init. Use `pwsh` or `PowerShell72`.
    - Check for `azurerm_virtual_machine` (Legacy). Should be `azurerm_linux_virtual_machine` or `azurerm_windows_virtual_machine`.

## 3. Logic & Configuration Audits

### A. Timezone & Localization

Different Azure resources expect different Timezone formats.

- **Rule**: Verify timezone formats against resource documentation.
- **Common Mappings**:
    - `azurerm_dev_test_global_vm_shutdown_schedule`: Requires **Windows Format** (e.g., `Singapore Standard Time`).
    - `azurerm_monitor_scheduled_query_rules_alert`: check docs.
    - `azurerm_automation_schedule`: Requires **IANA Format** (e.g., `Asia/Singapore`).
    - **Action**: If uncertain, use `search_web` with query "terraform azurerm <resource_name> timezone format".

### B. Identity & Usage

- **Rule**: Prefer Managed Identity over keys/secrets.
- **Check**:
    - If `Connect-AzAccount` is used in scripts, verify `identity { type = "SystemAssigned" }` is enabled on the VM.
    - Verify `azurerm_role_assignment` exists if the VM needs to access other resources (ACR, KeyVault).

### C. Cloud-Init Ordering

- **Rule**: Dependencies must inevitably define order.
- **Checks**:
    - **Users**: Do not use a user in `runcmd` before it is created in `users` section.
    - **Mounts**: Ensure mount points (directories) are created before mounting.
    - **Services**: `systemctl enable` and `start` must happen after config files are written.

## 4. Validation Tools

If you have shell access, run these commands to validate findings:

```bash
# 1. Terraform syntax check
terraform validate

# 2. Check for unescaped variables in a potential template file (adjust filename)
grep -E '\$\{[A-Za-z0-9_]+\}' cloud-init.yaml

# 3. YAML Syntax check
python3 -c "import yaml; yaml.safe_load(open('cloud-init.yaml'))"
```

## 5. Reporting Format

When referencing issues, output a markdown report in this format:

### Code Review Report

| Severity | File | Line | Description | Recommendation |
| :--- | :--- | :--- | :--- | :--- |
| **CRITICAL** | `cloud-init.yaml` | 15 | Unescaped bash variable `${PATH}` | Change to `$${PATH}` |
| **WARNING** | `main.tf` | 42 | Using deprecated `azurerm_virtual_machine` | Migrate to `azurerm_linux_virtual_machine` |
| **INFO** | `variables.tf` | - | Missing description for variable `vm_size` | Add description |
