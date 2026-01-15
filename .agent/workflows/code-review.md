---
description: How to thoroughly review Terraform and cloud-init code
---

# Terraform & Cloud-Init Code Review Workflow

When reviewing Terraform/IaC code, check these categories systematically. Always search the web for the latest Azure resource requirements.

## 1. Terraform Template String Escaping

In files processed by `templatefile()` or `templatestring()`:

- [ ] **Bash variables in templates** - All bash `${var}` must be escaped as `$${var}` 
- [ ] **Command substitutions** - All `$(command)` must be escaped as `$$(command)`
- [ ] **Legitimate Terraform vars** - Only actual Terraform variables should use `${var}` unescaped
- [ ] **Awk field references** - `$1`, `$5` etc. must be `$$1`, `$$5` in templates

**Example errors:**
```yaml
# WRONG - Terraform tries to interpolate these
PS1="${GREEN}\u${RESET}"
USAGE=$(df / | awk '{print $5}')

# CORRECT
PS1="$${GREEN}\u$${RESET}"
USAGE=$$(df / | awk '{print $$5}')
```

## 2. Resource-Specific Format Requirements

Different Azure resources require different formats for the same concept:

- [ ] **Timezones** - Check if resource uses Windows format (`Singapore Standard Time`) or IANA format (`Asia/Singapore`)
  - `azurerm_dev_test_global_vm_shutdown_schedule` → Windows format
  - `azurerm_automation_schedule` → IANA format
- [ ] **Time formats** - Check if HH:MM, HHMM, or ISO8601 required
- [ ] **Region names** - Check if display name or canonical name required

**Action:** Search web for each resource's documentation to verify expected formats.

## 3. Managed Identity & RBAC

- [ ] **Resources needing identity** - Does any resource call `Connect-AzAccount -Identity`? If yes, verify it has `identity { type = "SystemAssigned" }`
- [ ] **RBAC assignments** - Does any managed identity need to access other resources? Add appropriate role assignments
- [ ] **Scope of roles** - Use least-privilege scoping (specific resource vs resource group)

## 4. Cloud-Init Ordering Issues

- [ ] **Group dependencies** - Don't add users to groups that don't exist yet (e.g., `docker` group before Docker installed)
- [ ] **User creation timing** - `id -u username` may fail during cloud-init if user not created; use fallbacks
- [ ] **Service dependencies** - Explicitly `systemctl enable` and `start` services
- [ ] **write_files vs runcmd** - Scripts with `path:`, `owner:`, `permissions:`, `content:` belong in `write_files`, NOT `runcmd`

## 5. Deprecated/Outdated Resources

Search the web for current best practices:

- [ ] **PowerShell versions** - Use `PowerShell72` not `PowerShell` (5.1 is deprecated)
- [ ] **Module versions** - Use Az modules, not AzureRM (deprecated Feb 2025)
- [ ] **Run As Accounts** - Replaced by Managed Identities (retired Sep 2023)
- [ ] **Provider versions** - Check if using outdated provider versions

## 6. Error Handling & Resilience

- [ ] **Non-critical commands** - Add `|| true` to commands that shouldn't fail cloud-init
- [ ] **Mount operations** - `mount -a || true` prevents boot failures
- [ ] **Service restarts** - Reload configs after modification (e.g., `systemctl restart cron`)

## 7. Validation Commands

```bash
# Terraform syntax validation
terraform init -backend=false
terraform validate
terraform fmt -check

# YAML validation
python3 -c "import yaml; yaml.safe_load(open('cloud-init.yaml'))"

# Find unescaped bash vars in templates (should only show Terraform vars)
grep -E '\$\{[a-z_]+\}' cloud-init.yaml
```

## Checklist Summary

When asked to review code:

1. Read ALL files in the module, not just the one mentioned
2. Search web for each Azure resource's current documentation
3. Check all template files for escaping issues
4. Verify managed identities and RBAC are complete
5. Check for deprecated resources/patterns
6. Verify ordering dependencies in cloud-init
