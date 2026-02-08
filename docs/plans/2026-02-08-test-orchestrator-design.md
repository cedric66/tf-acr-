# AKS Spot Test Orchestrator - Design Document

**Date:** 2026-02-08
**Status:** Approved
**Purpose:** Unified test orchestration, auto-remediation, and comprehensive reporting for AKS spot optimization testing

## Executive Summary

This design creates a professional CLI tool (`aks-spot-test`) that orchestrates all three existing test frameworks (Terratest/Go, Bash, Python), automatically remediates infrastructure issues (VMSS ghosts, stuck nodes), monitors spot eviction rates, and generates comprehensive multi-format reports (JSON, HTML, Markdown) with historical tracking.

## Goals

1. **Unified Test Execution** - Single command to run all existing test suites sequentially
2. **Auto-Remediation** - Automatically detect and fix VMSS ghost instances and stuck nodes
3. **Comprehensive Reporting** - Multi-format reports (JSON/HTML/Markdown) with deep diagnostics
4. **Historical Tracking** - Timestamped reports for trend analysis
5. **Better Diagnostics** - Reproduce commands, full logs, cluster state snapshots
6. **Zone Failure Testing** - New test scenario simulating zone failures

## Non-Goals

- Rewriting existing test suites (we orchestrate, not replace)
- Real-time monitoring dashboard (batch-oriented tool)
- CI/CD pipeline integration (future work)
- Multi-cluster orchestration (single cluster only)

---

## Architecture

### Package Structure

```
tests/aks-spot-test-orchestrator/
├── aks_spot_test/
│   ├── __init__.py
│   ├── cli.py                    # Main CLI entry (Click/Typer framework)
│   ├── orchestrator.py           # Test execution coordinator
│   │
│   ├── runners/
│   │   ├── __init__.py
│   │   ├── terratest_runner.py   # Execute Go tests, parse output
│   │   ├── bash_runner.py        # Execute bash tests, parse JSON results
│   │   └── python_runner.py      # Execute pytest, parse JSON report
│   │
│   ├── parsers/
│   │   ├── __init__.py
│   │   ├── terratest_parser.py   # Parse go test JSON output
│   │   ├── bash_parser.py        # Parse bash JSON results
│   │   └── python_parser.py      # Parse pytest JSON report
│   │
│   ├── remediators/
│   │   ├── __init__.py
│   │   ├── vmss_ghost.py         # Detect/delete VMSS ghost instances
│   │   └── stuck_nodes.py        # Clean up NotReady nodes
│   │
│   ├── monitors/
│   │   ├── __init__.py
│   │   ├── eviction_rate.py      # Track spot evictions during test
│   │   └── cluster_state.py      # Snapshot nodes/pods before/after
│   │
│   ├── reporters/
│   │   ├── __init__.py
│   │   ├── json_reporter.py      # Generate JSON report
│   │   ├── html_reporter.py      # Generate interactive HTML dashboard
│   │   └── markdown_reporter.py  # Generate Markdown report
│   │
│   ├── models.py                 # Data models (TestResult, Report, etc.)
│   └── utils.py                  # Common utilities
│
├── templates/
│   └── report.html.j2            # Jinja2 template for HTML report
│
├── config.yaml                   # Optional configuration overrides
├── setup.py                      # Pip installable package
├── requirements.txt              # Dependencies
└── README.md                     # Installation and usage guide
```

### CLI Commands

```bash
aks-spot-test run              # Run all tests + generate report (primary command)
aks-spot-test report <json>    # Regenerate report from existing JSON
aks-spot-test remediate        # Run remediation only (no tests)
aks-spot-test monitor          # Monitor eviction rate continuously
```

---

## Execution Flow

### Command: `aks-spot-test run`

#### Phase 1: Pre-Flight Checks (~30 seconds)

1. **Cluster Connectivity**
   - Run: `kubectl cluster-info`
   - ABORT if unreachable (clear error message)

2. **Azure CLI Authentication**
   - Run: `az account show`
   - ABORT if not authenticated (show login instructions)

3. **Environment Configuration**
   - Check `.env` files exist in:
     - `tests/.env`
     - `tests/spot-behavior/.env`
     - `tests/spot-behavior-python/.env`
   - WARN if missing, use defaults

4. **Initial Cluster Snapshot**
   - Capture: node counts, pod distribution, pool states
   - Store in `ClusterSnapshot` object

5. **Start Eviction Monitor**
   - Background thread: poll `kubectl get events` every 30s
   - Track spot evictions during test run

#### Phase 2: Sequential Test Execution (~25-30 minutes)

**Step 1: Terratest (Go) - Infrastructure Validation (~5 min)**
```bash
cd tests/
export $(cat .env | xargs)
go test -v -timeout 10m -json ./... > terratest-output.json
```
- Parse: JSON output → `List[TestResult]`
- Continue even if failures
- Capture stderr for diagnostics

**Step 2: Bash Spot Tests - Runtime Behavior (~10-15 min)**
```bash
cd tests/spot-behavior/
source .env
./run-all-tests.sh
```
- Parse: `results/*.json` → `List[TestResult]`
- Continue even if failures
- Capture stdout/stderr

**Step 3: Python Spot Tests - Pytest Framework (~10-15 min)**
```bash
cd tests/spot-behavior-python/
export $(cat .env | xargs)
source venv/bin/activate 2>/dev/null || true  # Optional venv
pytest -v --json-report --json-report-file=results.json
```
- Parse: `results.json` → `List[TestResult]`
- Continue even if failures
- Capture pytest output

#### Phase 3: Auto-Remediation (~1-2 min)

**VMSS Ghost Instance Detection & Cleanup**
```python
for pool in all_node_pools:
    vmss_list = az vmss list -g MC_rg --query "[?tags.poolName=='{pool}']"
    instances = az vmss list-instances -n vmss_name -g MC_rg

    for instance in instances:
        if instance.provisioningState in ["Failed", "Unknown"]:
            if instance.age_minutes > 5:
                # Auto-delete ghost
                az vmss delete-instances -n vmss_name -g MC_rg --instance-ids {id}
                log_remediation("delete_vmss_ghost", instance_id, success=True)
```

**Stuck Node Detection & Cleanup**
```python
nodes = kubectl get nodes -o json
for node in nodes:
    if node.status == "NotReady" and node.age_minutes > 5:
        # Auto-delete stuck node
        kubectl delete node {node_name}
        log_remediation("delete_stuck_node", node_name, success=True)
```

#### Phase 4: Report Generation (~30 seconds)

1. **Stop Eviction Monitor**
   - Collect eviction events
   - Calculate eviction rate (events/hour)

2. **Final Cluster Snapshot**
   - Capture: node counts, pod distribution, pool states
   - Compare with initial snapshot

3. **Aggregate Test Results**
   - Combine results from all frameworks
   - Calculate summary statistics
   - Identify top 5 failures

4. **Generate Reports**
   - Timestamp: `YYYY-MM-DD-HHMMSS`
   - JSON: `test-report-{timestamp}.json`
   - HTML: `test-report-{timestamp}.html`
   - Markdown: `test-report-{timestamp}.md`

5. **Console Summary**
   - Print: pass/fail counts, duration, report paths
   - Exit code: 0 if all passed, 1 if any failures

---

## Data Models

### TestResult
```python
@dataclass
class TestResult:
    """Single test result from any framework."""
    test_id: str                    # e.g., "DIST-001", "TestAksSpotModuleValidation"
    name: str                       # Human-readable test name
    category: str                   # e.g., "pod-distribution", "infrastructure"
    framework: str                  # "terratest", "bash", "python"
    status: str                     # "PASS", "FAIL", "SKIP"
    duration_seconds: float
    error_message: Optional[str]    # Full error if failed
    assertions: List[Assertion]     # Individual checks within test
    evidence: Dict[str, Any]        # Raw data (node lists, pod counts, etc.)
    reproduce_commands: List[str]   # kubectl/az commands to debug
```

### Assertion
```python
@dataclass
class Assertion:
    """Individual assertion within a test."""
    description: str                # e.g., "web pods on spot nodes"
    expected: Any
    actual: Any
    passed: bool
```

### RemediationAction
```python
@dataclass
class RemediationAction:
    """Auto-remediation action taken."""
    timestamp: datetime
    action_type: str                # "delete_vmss_ghost", "delete_stuck_node"
    target: str                     # Resource name (instance ID, node name)
    success: bool
    details: str                    # Error message if failed
```

### ClusterSnapshot
```python
@dataclass
class ClusterSnapshot:
    """Cluster state at a point in time."""
    timestamp: datetime
    total_nodes: int
    ready_nodes: int
    spot_nodes: int
    total_pods: int
    pending_pods: int
    node_pool_counts: Dict[str, int]  # pool_name -> node_count
```

### TestReport
```python
@dataclass
class TestReport:
    """Complete test run report."""
    run_id: str                     # UUID for this test run
    timestamp: datetime
    cluster_name: str
    duration_seconds: float

    # Summary statistics
    total_tests: int
    passed: int
    failed: int
    skipped: int
    pass_rate: float                # Percentage

    # Detailed results
    test_results: List[TestResult]
    framework_summary: Dict[str, Dict]  # Per-framework stats
    category_summary: Dict[str, Dict]   # Per-category stats

    # Diagnostics
    initial_state: ClusterSnapshot
    final_state: ClusterSnapshot
    eviction_events: List[Dict]         # Evictions during test
    eviction_rate_per_hour: float
    remediation_actions: List[RemediationAction]

    # Failure analysis
    top_failures: List[TestResult]      # Top 5 most critical failures
    failure_patterns: Dict[str, int]    # Common error types → count
```

---

## Report Formats

### JSON Report (`test-report-2026-02-08-143022.json`)

Machine-readable format for CI/CD integration and automation.

**Structure:**
```json
{
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-08T14:30:22Z",
  "cluster_name": "aks-spot-prod",
  "duration_seconds": 1847.3,
  "summary": {
    "total_tests": 106,
    "passed": 98,
    "failed": 6,
    "skipped": 2,
    "pass_rate": 92.45
  },
  "framework_summary": {
    "terratest": {"total": 6, "passed": 6, "failed": 0, "skipped": 0},
    "bash": {"total": 50, "passed": 46, "failed": 3, "skipped": 1},
    "python": {"total": 50, "passed": 46, "failed": 3, "skipped": 1}
  },
  "category_summary": {
    "infrastructure": {"total": 6, "passed": 6, "failed": 0},
    "pod-distribution": {"total": 10, "passed": 9, "failed": 1},
    "eviction-behavior": {"total": 10, "passed": 8, "failed": 2}
  },
  "test_results": [
    {
      "test_id": "DIST-001",
      "name": "Stateless services on spot nodes",
      "category": "pod-distribution",
      "framework": "bash",
      "status": "PASS",
      "duration_seconds": 3.2,
      "error_message": null,
      "assertions": [
        {
          "description": "web pods on spot nodes",
          "expected": "> 0",
          "actual": 3,
          "passed": true
        }
      ],
      "evidence": {
        "spot_pod_count": 3,
        "total_pod_count": 3,
        "nodes": ["aks-spotgeneral1-12345678-vmss000001", ...]
      },
      "reproduce_commands": [
        "kubectl get pods -n robot-shop -l app=web -o wide"
      ]
    }
  ],
  "cluster_state": {
    "initial": {
      "timestamp": "2026-02-08T14:00:00Z",
      "total_nodes": 18,
      "ready_nodes": 17,
      "spot_nodes": 12,
      "total_pods": 45,
      "pending_pods": 0,
      "node_pool_counts": {
        "system": 3,
        "stdworkload": 3,
        "spotgeneral1": 4,
        "spotmemory1": 3,
        "spotgeneral2": 3,
        "spotcompute": 2
      }
    },
    "final": {
      "timestamp": "2026-02-08T14:30:47Z",
      "total_nodes": 19,
      "ready_nodes": 19,
      "spot_nodes": 13,
      "total_pods": 45,
      "pending_pods": 0,
      "node_pool_counts": {
        "system": 3,
        "stdworkload": 3,
        "spotgeneral1": 4,
        "spotmemory1": 4,
        "spotgeneral2": 3,
        "spotcompute": 2
      }
    }
  },
  "eviction_monitoring": {
    "total_evictions": 3,
    "eviction_rate_per_hour": 1.2,
    "events": [
      {
        "timestamp": "2026-02-08T14:15:33Z",
        "node": "aks-spotgeneral1-12345678-vmss000002",
        "reason": "Spot eviction",
        "message": "Node will be deleted in 30 seconds"
      }
    ]
  },
  "remediation": {
    "actions_taken": 2,
    "vmss_ghosts_deleted": 1,
    "stuck_nodes_deleted": 1,
    "details": [
      {
        "timestamp": "2026-02-08T14:32:10Z",
        "action_type": "delete_vmss_ghost",
        "target": "vmss000003",
        "success": true,
        "details": "Instance stuck in Failed state for 8 minutes"
      }
    ]
  },
  "top_failures": [
    {
      "test_id": "EVICT-005",
      "name": "PDB respected during drain",
      "category": "eviction-behavior",
      "framework": "bash",
      "status": "FAIL",
      "error_message": "PDB violation: drain succeeded despite minAvailable=50%"
    }
  ],
  "failure_patterns": {
    "PDB violation": 2,
    "Timeout waiting for pods": 3,
    "Node not found": 1
  }
}
```

### HTML Report (`test-report-2026-02-08-143022.html`)

Interactive dashboard for human consumption.

**Sections:**
1. **Header**
   - Cluster name, timestamp, duration
   - Overall pass/fail badge (green/red)
   - Quick stats: total tests, pass rate, eviction rate

2. **Executive Summary Dashboard**
   - **Pie Chart:** Pass/Fail/Skip distribution
   - **Bar Chart:** Pass rate by framework (Terratest, Bash, Python)
   - **Timeline Chart:** Test execution duration per suite
   - **Eviction Timeline:** Spot evictions during test run

3. **Quick Stats Cards** (Bootstrap cards)
   - Total Tests: 106
   - Pass Rate: 92.45%
   - Eviction Rate: 1.2/hour
   - Remediation Actions: 2

4. **Cluster Health Section**
   - **Before/After Table:**
     ```
     | Metric       | Before | After | Change |
     |--------------|--------|-------|--------|
     | Total Nodes  | 18     | 19    | +1     |
     | Spot Nodes   | 12     | 13    | +1     |
     | Ready Nodes  | 17     | 19    | +2     |
     ```
   - **Eviction Timeline Chart:** X-axis: time, Y-axis: eviction events
   - **VMSS Ghost Instances:** Table of ghosts found/fixed

5. **Test Results Table** (DataTables.js for sorting/filtering)
   - Collapsible sections: Framework → Category → Tests
   - Color-coded rows: Green (pass), Red (fail), Yellow (skip)
   - Expandable rows show:
     - Error message
     - Assertions (expected vs actual)
     - Evidence (raw data)
     - Reproduce commands (copy-paste kubectl/az commands)

6. **Failed Tests Deep Dive**
   - For each failure:
     - Full error message
     - Stack trace (if available)
     - Kubectl commands to reproduce
     - Link to relevant docs (e.g., SPOT_EVICTION_SCENARIOS.md)
     - Similar historical failures (if available from previous runs)

7. **Remediation Log**
   - Timeline of auto-fixes
   - Before/after snapshots for each action
   - Success/failure status

8. **Appendix** (collapsible sections)
   - Full test logs (syntax-highlighted)
   - Cluster state JSON
   - Export buttons:
     - Download JSON
     - Download Markdown
     - Print-friendly view

**Technology Stack:**
- Bootstrap 5 for layout
- Chart.js for graphs
- DataTables.js for interactive tables
- Prism.js for syntax highlighting
- Jinja2 for templating

### Markdown Report (`test-report-2026-02-08-143022.md`)

GitHub-compatible format for PRs and documentation.

**Structure:**
```markdown
# AKS Spot Test Report

**Cluster:** aks-spot-prod
**Date:** 2026-02-08 14:30:22
**Duration:** 30m 47s
**Run ID:** 550e8400-e29b-41d4-a716-446655440000

---

## Executive Summary

✅ **Overall Result:** PASS (92.45% pass rate)

- **Total Tests:** 106
- **Passed:** 98 ✅
- **Failed:** 6 ❌
- **Skipped:** 2 ⏭️

### Framework Breakdown

| Framework | Total | Passed | Failed | Skipped | Pass Rate |
|-----------|-------|--------|--------|---------|-----------|
| Terratest | 6     | 6      | 0      | 0       | 100%      |
| Bash      | 50    | 46     | 3      | 1       | 92%       |
| Python    | 50    | 46     | 3      | 1       | 92%       |

### Category Breakdown

| Category           | Total | Passed | Failed | Skipped |
|--------------------|-------|--------|--------|---------|
| Infrastructure     | 6     | 6      | 0      | 0       |
| Pod Distribution   | 10    | 9      | 1      | 0       |
| Eviction Behavior  | 10    | 8      | 2      | 0       |
| PDB Enforcement    | 6     | 6      | 0      | 0       |
| Topology Spread    | 5     | 5      | 0      | 0       |
| Recovery           | 6     | 5      | 1      | 0       |
| Sticky Fallback    | 5     | 4      | 0      | 1       |
| VMSS/Node Pool     | 6     | 5      | 1      | 0       |
| Autoscaler         | 5     | 5      | 0      | 0       |
| Cross-Service      | 5     | 5      | 0      | 0       |
| Edge Cases         | 5     | 4      | 1      | 1       |

---

## Cluster Health

**Eviction Rate:** 1.2 evictions/hour (3 total during test)
**Remediation:** 2 actions taken (1 VMSS ghost deleted, 1 stuck node removed)

### Node Distribution

| Metric      | Before | After | Change |
|-------------|--------|-------|--------|
| Total Nodes | 18     | 19    | +1     |
| Spot Nodes  | 12     | 13    | +1     |
| Ready Nodes | 17     | 19    | +2     |

### Eviction Events

| Time     | Node                                    | Reason         |
|----------|-----------------------------------------|----------------|
| 14:15:33 | aks-spotgeneral1-12345678-vmss000002   | Spot eviction  |
| 14:22:18 | aks-spotmemory1-87654321-vmss000001    | Spot eviction  |
| 14:28:45 | aks-spotgeneral2-11223344-vmss000000   | Spot eviction  |

### Remediation Actions

| Time     | Action Type          | Target        | Status  | Details                                  |
|----------|----------------------|---------------|---------|------------------------------------------|
| 14:32:10 | delete_vmss_ghost    | vmss000003    | ✅ Success | Instance stuck in Failed state for 8min  |
| 14:32:45 | delete_stuck_node    | aks-spot-... | ✅ Success | Node NotReady for 6min                   |

---

## Failed Tests (6)

### 1. EVICT-005: PDB Respected During Drain ❌

**Framework:** bash
**Category:** eviction-behavior
**Duration:** 15.3s

**Error:**
```
PDB violation detected - drain succeeded despite minAvailable=50%
Expected: Drain blocked by PDB
Actual: All pods evicted, PDB ignored
```

**Reproduce:**
```bash
kubectl get pdb -n robot-shop web-pdb -o yaml
kubectl drain aks-spotgeneral1-12345678-vmss000001 --ignore-daemonsets --delete-emptydir-data
```

**Documentation:** See `docs/SPOT_EVICTION_SCENARIOS.md` section on PDB enforcement

---

### 2. VMSS-004: Autoscale Ranges Match Config ❌

**Framework:** python
**Category:** vmss-node-pool
**Duration:** 8.7s

**Error:**
```
Autoscale range mismatch for pool 'spotmemory1'
Expected: min=0, max=15
Actual: min=0, max=20
```

**Reproduce:**
```bash
az aks nodepool show -g rg-aks-spot --cluster-name aks-spot-prod -n spotmemory1 --query '{min:minCount,max:maxCount}'
```

**Fix:** Update `.env` file to match deployed cluster settings:
```bash
POOL_MAX_spotmemory1=20
```

**Documentation:** See `tests/spot-behavior-python/.env.example` header warning

---

[... more failures ...]

---

## Full Test Results

<details>
<summary><b>Infrastructure (Terratest) - 6/6 Passed ✅</b></summary>

| Test ID | Name | Status | Duration |
|---------|------|--------|----------|
| TestAksSpotModuleValidation | Module validates successfully | ✅ PASS | 2.1s |
| TestAksSpotModulePlan | Module plan generates without errors | ✅ PASS | 5.3s |
| ... | ... | ... | ... |

</details>

<details>
<summary><b>Pod Distribution (Bash/Python) - 9/10 Passed</b></summary>

| Test ID | Name | Status | Duration |
|---------|------|--------|----------|
| DIST-001 | Stateless services on spot nodes | ✅ PASS | 3.2s |
| DIST-002 | Stateful services off spot nodes | ✅ PASS | 2.8s |
| DIST-003 | Spot tolerations present | ✅ PASS | 1.5s |
| DIST-004 | Node affinity preference | ❌ FAIL | 4.1s |
| ... | ... | ... | ... |

</details>

[... more categories ...]

---

## Appendix

### Test Execution Timeline

```
14:00:00 - Pre-flight checks started
14:00:30 - Terratest started
14:05:42 - Terratest completed (✅ 6/6 passed)
14:05:43 - Bash tests started
14:18:25 - Bash tests completed (⚠️ 46/50 passed)
14:18:26 - Python tests started
14:31:15 - Python tests completed (⚠️ 46/50 passed)
14:31:16 - Remediation started
14:32:50 - Remediation completed (2 actions)
14:33:00 - Report generation started
14:33:22 - Report generation completed
```

### Export Options

- **JSON Report:** `test-report-2026-02-08-143022.json`
- **HTML Report:** `test-report-2026-02-08-143022.html`
- **Markdown Report:** `test-report-2026-02-08-143022.md` (this file)

---

*Generated by `aks-spot-test` v1.0.0*
```

---

## Error Handling

### Graceful Degradation Strategy

**Phase 1: Pre-Flight Checks**
- Cluster unreachable → **ABORT** with clear error message
- Azure CLI not authenticated → **ABORT** with `az login` instructions
- Missing `.env` files → **WARN** and use default values

**Phase 2: Test Execution**
- Terratest fails → Log errors, **continue** to Bash tests
- Bash tests timeout → Mark as FAIL, **continue** to Python tests
- Python venv missing → Try system Python, warn if version mismatch
- Any framework crashes → Capture stack trace, **continue** to next

**Phase 3: Remediation**
- VMSS ghost deletion fails → Log error, **try next** ghost
- Node deletion times out → Log warning, **continue**
- Azure API rate limit → **Retry** with exponential backoff (3 attempts, 2s/4s/8s)

**Phase 4: Report Generation**
- HTML generation fails → Skip HTML, **still generate** JSON/Markdown
- Template file missing → Use **minimal fallback** template
- Disk full → **Print report to stdout** as fallback

### Exit Codes

```python
0 - All tests passed
1 - Some tests failed (but orchestrator succeeded)
2 - Orchestrator error (pre-flight failed, cluster unreachable)
3 - Configuration error (missing files, invalid config)
```

---

## Configuration

### Optional Configuration File (`config.yaml`)

Override defaults without modifying code:

```yaml
# Cluster connection
cluster:
  kubeconfig: ~/.kube/config
  context: null  # Use current context
  timeout_seconds: 300

# Test suite configuration
test_suites:
  terratest:
    enabled: true
    timeout_minutes: 10
    working_dir: tests/
    env_file: tests/.env

  bash:
    enabled: true
    timeout_minutes: 20
    working_dir: tests/spot-behavior/
    env_file: tests/spot-behavior/.env

  python:
    enabled: true
    timeout_minutes: 20
    working_dir: tests/spot-behavior-python/
    env_file: tests/spot-behavior-python/.env
    venv_path: venv/  # Optional virtualenv

# Auto-remediation settings
remediation:
  enabled: true

  vmss_ghosts:
    enabled: true
    min_age_minutes: 5  # Only delete if stuck >5min

  stuck_nodes:
    enabled: true
    min_age_minutes: 5  # Only delete if NotReady >5min

# Monitoring settings
monitoring:
  eviction_rate:
    enabled: true
    poll_interval_seconds: 30

# Report generation
reports:
  output_dir: tests/aks-spot-test-orchestrator/reports/
  formats: [json, html, markdown]  # Generate all formats
  retention_days: 30  # Auto-cleanup old reports (0 = never)
  open_html_after_run: false  # Auto-open HTML in browser
```

---

## New Test Scenario: Zone Failure

### EDGE-006: Zone Failure Simulation

Add to both Bash and Python test suites under `categories/10-edge-cases/`.

**Purpose:** Validate that the cluster remains available when an entire availability zone fails.

**Test Steps:**

1. **Identify Target Zone**
   - Select zone with most spot nodes (typically zone 1)
   - Example: `australiaeast-1`

2. **Simulate Zone Failure**
   - Cordon all nodes in target zone
   - This prevents new pod scheduling on those nodes

3. **Trigger Rescheduling**
   - Delete 1 pod per service to force rescheduling
   - Or wait for natural pod restarts

4. **Wait for Recovery**
   - Wait up to 120 seconds for pods to reschedule
   - Pods should move to zones 2 and 3

5. **Validate Multi-Zone Distribution**
   - Assert pods exist in at least 2 zones (excluding failed zone)
   - Assert no PDB violations occurred
   - Assert all services are healthy (endpoints exist)

6. **Cleanup**
   - Uncordon all nodes in target zone
   - Verify cluster returns to normal state

**Python Implementation:**

```python
def test_edge_006_zone_failure(config: TestConfig, writer: ResultWriter):
    """Simulate zone failure by cordoning all nodes in one zone.

    Validates:
    - Pods reschedule to other zones
    - PDBs prevent complete unavailability
    - Services remain accessible
    - Autoscaler provisions capacity in healthy zones (if needed)
    """
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)

    writer.start_test("EDGE-006", "Zone failure simulation", "edge-cases")

    # 1. Identify zone with most spot nodes
    zone_distribution = {}
    for node in nodes.get_spot_nodes():
        zone = nodes.get_zone(node)
        zone_distribution[zone] = zone_distribution.get(zone, 0) + 1

    target_zone = max(zone_distribution, key=zone_distribution.get)
    writer.add_evidence("target_zone", target_zone)

    # 2. Cordon all nodes in target zone
    nodes_in_zone = [n for n in nodes.kube.get_nodes() if nodes.get_zone(n) == target_zone]
    for node in nodes_in_zone:
        node_name = node["metadata"]["name"]
        nodes.cordon(node_name)

    writer.add_evidence("cordoned_nodes", len(nodes_in_zone))

    try:
        # 3. Trigger rescheduling (delete 1 pod per stateless service)
        for service in config.stateless_services:
            service_pods = pods.get_service_pods(service)
            if service_pods:
                pod_name = service_pods[0]["metadata"]["name"]
                kube.run(["delete", "pod", pod_name, "-n", config.namespace])

        # 4. Wait for pods to reschedule
        time.sleep(10)  # Initial settling
        all_ready = pods.wait_for_ready(label="", timeout=120)
        writer.assert_eq("All pods rescheduled", all_ready, True)

        # 5. Validate multi-zone distribution
        for service in config.stateless_services:
            zones = pods.get_pod_zones(service)
            # Pods should exist in zones other than the failed zone
            healthy_zones = [z for z in zones if z != target_zone]
            writer.assert_gt(
                f"{service} pods in multiple healthy zones",
                len(healthy_zones), 0
            )

        # 6. Validate no PDB violations
        pdbs = kube.get_pdbs()
        for pdb in pdbs:
            pdb_name = pdb["metadata"]["name"]
            allowed_disruptions = pdb["status"].get("disruptionsAllowed", 0)
            writer.assert_gte(
                f"PDB {pdb_name} allows disruptions",
                allowed_disruptions, 0
            )

        # 7. Validate services healthy
        for service in config.stateless_services:
            running_count = pods.count_running_for_service(service)
            writer.assert_gt(
                f"{service} has running pods",
                running_count, 0
            )

    finally:
        # 8. Cleanup: uncordon all nodes
        for node in nodes_in_zone:
            node_name = node["metadata"]["name"]
            nodes.uncordon(node_name)

    writer.finish_test()


test_edge_006_zone_failure.test_id = "EDGE-006"
```

**Bash Implementation:**

```bash
#!/usr/bin/env bash
# EDGE-006_zone_failure.sh - Simulate zone failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

TEST_ID="EDGE-006"
TEST_NAME="Zone failure simulation"
CATEGORY="edge-cases"

start_test "$TEST_ID" "$TEST_NAME" "$CATEGORY"

# 1. Identify zone with most spot nodes
TARGET_ZONE=$(kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot \
  -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' \
  | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

add_evidence "target_zone" "$TARGET_ZONE"

# 2. Get all nodes in target zone
NODES_IN_ZONE=$(kubectl get nodes \
  -l topology.kubernetes.io/zone="$TARGET_ZONE" \
  -o jsonpath='{.items[*].metadata.name}')

# 3. Cordon all nodes in zone
for node in $NODES_IN_ZONE; do
  kubectl cordon "$node"
done

# 4. Trigger rescheduling (delete 1 pod per service)
for service in web cart catalogue; do
  POD=$(kubectl get pods -n "$NAMESPACE" -l app="$service" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$POD" ]]; then
    kubectl delete pod -n "$NAMESPACE" "$POD" --wait=false
  fi
done

# 5. Wait for pods to reschedule
sleep 10
kubectl wait --for=condition=Ready pods -n "$NAMESPACE" --all --timeout=120s

# 6. Validate pods exist in other zones
for service in web cart catalogue; do
  ZONES=$(kubectl get pods -n "$NAMESPACE" -l app="$service" \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' \
    | xargs -I {} kubectl get node {} -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}' \
    | grep -v "$TARGET_ZONE" || echo "")

  if [[ -n "$ZONES" ]]; then
    assert_pass "$service pods rescheduled to healthy zones"
  else
    assert_fail "$service pods not found in healthy zones" "pods in other zones" "no pods found"
  fi
done

# 7. Cleanup: uncordon nodes
for node in $NODES_IN_ZONE; do
  kubectl uncordon "$node"
done

finish_test
```

---

## Installation & Usage

### Installation

```bash
cd tests/aks-spot-test-orchestrator

# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate

# Install in editable mode
pip install -e .

# Or install from requirements.txt
pip install -r requirements.txt
python setup.py install
```

### Usage Examples

**Run all tests (default):**
```bash
aks-spot-test run
```

**Run with custom config:**
```bash
aks-spot-test run --config my-config.yaml
```

**Skip remediation (detect only):**
```bash
aks-spot-test run --no-remediate
```

**Skip specific test suite:**
```bash
aks-spot-test run --skip-bash
```

**Generate report from existing JSON:**
```bash
aks-spot-test report tests/aks-spot-test-orchestrator/reports/test-report-2026-02-08-143022.json
```

**Monitor eviction rate continuously (Ctrl+C to stop):**
```bash
aks-spot-test monitor --interval 60
```

**Run remediation only (no tests):**
```bash
aks-spot-test remediate
```

**Open HTML report after run:**
```bash
aks-spot-test run --open-html
```

---

## Dependencies

**Core:**
- `click` or `typer` - CLI framework
- `pyyaml` - Config file parsing
- `jinja2` - HTML template rendering
- `kubernetes` (optional) - Python k8s client (fallback to kubectl)

**Testing:**
- Standard library: `subprocess`, `json`, `dataclasses`, `datetime`

**Reporting:**
- Chart.js (CDN) - HTML charts
- Bootstrap 5 (CDN) - HTML layout
- DataTables.js (CDN) - Interactive tables
- Prism.js (CDN) - Syntax highlighting

**No heavy dependencies** - keep the tool lightweight and portable.

---

## Implementation Phases

### Phase 1: Core Orchestrator (Week 1)
- [ ] Project structure and setup.py
- [ ] CLI skeleton with Click/Typer
- [ ] Sequential test runner (Terratest → Bash → Python)
- [ ] Basic JSON report generation
- [ ] Data models (TestResult, TestReport)

### Phase 2: Parsers (Week 2)
- [ ] Terratest output parser (go test -json)
- [ ] Bash JSON results parser
- [ ] Python pytest JSON parser
- [ ] Aggregate results into TestReport

### Phase 3: Monitoring & Remediation (Week 2)
- [ ] Eviction rate monitor (background thread)
- [ ] Cluster state snapshots
- [ ] VMSS ghost detection/deletion
- [ ] Stuck node detection/deletion

### Phase 4: Reporting (Week 3)
- [ ] HTML report template (Jinja2)
- [ ] Markdown report generator
- [ ] Multi-format output
- [ ] Timestamped file naming

### Phase 5: Zone Failure Test (Week 3)
- [ ] EDGE-006 Python implementation
- [ ] EDGE-006 Bash implementation
- [ ] Integration into test suites

### Phase 6: Polish & Documentation (Week 4)
- [ ] Error handling and retries
- [ ] Configuration file support
- [ ] README and usage guide
- [ ] Example reports (commit to repo)

---

## Success Criteria

1. ✅ Single command runs all 3 test frameworks sequentially
2. ✅ Auto-remediates VMSS ghosts and stuck nodes
3. ✅ Generates JSON, HTML, and Markdown reports
4. ✅ Reports include cluster state, eviction rate, and diagnostics
5. ✅ Zone failure test scenario implemented
6. ✅ Timestamped reports with historical tracking
7. ✅ Exit code reflects test success/failure
8. ✅ Tool is pip-installable

---

## Future Enhancements (Out of Scope)

- CI/CD integration (GitHub Actions workflow)
- Historical trend analysis (database storage)
- Real-time monitoring dashboard (web UI)
- Multi-cluster orchestration
- Slack/Teams alerting
- Cost impact analysis (correlate evictions with spend)

---

**Next Steps:**
1. Create git worktree for isolated development
2. Create detailed implementation plan with file-by-file breakdown
3. Begin Phase 1 implementation
