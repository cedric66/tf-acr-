---
description: Maintenance workflow for the Consolidated Project Brief
---

# Project Maintenance Workflow

This workflow ensures that the project's documentation remains accurate and up-to-date as the codebase evolves.

## 📋 Steps for AI Agents

Whenever a task is completed that affects the project's scope, architecture, metrics, or roadmap, perform the following:

1. **Review Changes**: Analyze the work done (code changes, new documents, etc.).
2. **Identify Impact**: Determine if the change affects any section of the [CONSOLIDATED_PROJECT_BRIEF.md](../../CONSOLIDATED_PROJECT_BRIEF.md).
3. **Update the Brief**:
    - Update the **"Last Updated"** date.
    - Revise relevant sections (e.g., add new deliverables, update metrics, or modify the roadmap).
    - Ensure the "Status" reflects the current project state.
4. **Link to Details**: If new detailed documentation was created, ensure it is linked in the "Key Deliverables" or "Supporting Documents" section of the brief.
5. **Privacy Check**: Ensure NO absolute file paths (e.g., `/Users/username/...`) or system-specific URIs are added to any documentation. Always use relative paths.

## 🧪 Verification
- Ensure the brief still provides a clear, high-level overview.
- Check that all links within the brief are valid.
- Verify that the summary reflects the absolute latest state of the repository.
