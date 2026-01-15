# AI Maintenance Instructions

This file serves as a guide for AI agents (and human maintainers) working on this `scripts/` directory.

## Rule: Updating Documentation

**Whenever you add a new script to this directory, you MUST update `README.md`.**

### Checklist for New Scripts:
1.  **Add a Section**: Create a new subsection in `README.md` under "Scripts".
2.  **Description**: Briefly explain what the script does (Value Proposition).
3.  **Usage**: Provide the exact command line usage, including new arguments.
4.  **Requirements**: If the script adds new Python dependencies, update `requirements.txt`.
5.  **Validation**: Verify the script runs (or passes syntax check) before checking it in.

### Style Guide
- **Python**: Follow PEP 8 where possible. Use `azure-identity` for auth.
- **Bash**: Ensure scripts are executable (`chmod +x`). Use `az` CLI for lightweight tasks.
- **Output**: Use `tabulate` for Python scripts to print pretty tables. Use colors (`colorama` or ANSI codes) to highlight "Bad" (Red) or "Good" (Green) status.

## Config File Schema
If the script targets multiple resources, strict adherence to `utils.load_config` schema is required:
```json
{
  "targets": [
    {
      "subscription_id": "00000-...",
      "resource_groups": ["rg1", "rg2"], // Optional
      "clusters": ["cluster1"] // Optional
    }
  ]
}
```
