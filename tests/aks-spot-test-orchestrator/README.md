# AKS Spot Test Orchestrator

Unified test orchestration, auto-remediation, and comprehensive reporting for AKS spot optimization testing.

## Features

- ✅ **Unified Test Execution** - Run all 3 test frameworks (Terratest, Bash, Python) sequentially
- ✅ **Auto-Remediation** - Automatically detect and fix VMSS ghost instances and stuck nodes
- ✅ **Multi-Format Reports** - Generate JSON, HTML, and Markdown reports
- ✅ **Eviction Monitoring** - Track spot eviction rate during test runs
- ✅ **Comprehensive Diagnostics** - Cluster snapshots, reproduce commands, failure analysis
- ✅ **Historical Tracking** - Timestamped reports for trend analysis

## Installation

```bash
cd tests/aks-spot-test-orchestrator

# Install in editable mode (recommended for development)
pip install -e .

# Or install from requirements.txt
pip install -r requirements.txt
python setup.py install
```

## Quick Start

### Configure Environment

**First time setup:**

```bash
cd tests/aks-spot-test-orchestrator
cp .env.example .env
nano .env  # Edit with your cluster details
```

The orchestrator automatically loads `.env` and passes configuration to all test suites.

### Run All Tests

```bash
# Run all tests with default configuration
aks-spot-test run

# Run with custom config
aks-spot-test run --config my-config.yaml

# Skip auto-remediation
aks-spot-test run --no-remediate

# Skip specific test suites
aks-spot-test run --skip-bash --skip-python
```

### Generate Report from JSON

```bash
aks-spot-test report reports/test-report-2026-02-08-143022.json
```

### Run Auto-Remediation Only

```bash
aks-spot-test remediate
```

### Monitor Eviction Rate

```bash
# Monitor continuously (Ctrl+C to stop)
aks-spot-test monitor --interval 60
```

## Prerequisites

1. **Deployed AKS cluster** with spot node pools
2. **kubectl** configured to connect to the cluster
3. **Azure CLI** authenticated (`az login`)
4. **Python 3.8+** (for Python tests)
   ```bash
   python3 --version
   ```
5. **Configuration file:**
   ```bash
   cd tests/aks-spot-test-orchestrator
   cp .env.example .env
   # Edit .env with your cluster details
   ```

## Python Test Environment

The orchestrator automatically sets up the Python test environment:

1. **Creates virtual environment** if it doesn't exist (`venv/`)
2. **Installs dependencies** from `../spot-behavior-python/requirements.txt`
3. **Runs pytest** within the isolated environment

No manual venv setup is required—the orchestrator handles it automatically during test execution.

## Configuration

### Default Configuration

The tool uses sensible defaults, but you can customize via `config.yaml`:

```yaml
# config.yaml example
test_suites:
  terratest:
    enabled: true
    timeout_minutes: 10
    working_dir: ../

  bash:
    enabled: true
    timeout_minutes: 20
    working_dir: ../spot-behavior

  python:
    enabled: true
    timeout_minutes: 20
    working_dir: ../spot-behavior-python
    venv_path: venv

remediation:
  enabled: true
  vmss_ghosts:
    enabled: true
    min_age_minutes: 5
  stuck_nodes:
    enabled: true
    min_age_minutes: 5

monitoring:
  eviction_rate:
    enabled: true
    poll_interval_seconds: 30

reports:
  output_dir: ./reports
  formats: [json, html, markdown]
  retention_days: 30
```

### Environment Variables

The orchestrator uses a **centralized `.env` file** in the orchestrator directory:

```bash
tests/aks-spot-test-orchestrator/.env
```

**Key configuration variables:**

```bash
# === Cluster Identity (REQUIRED) ===
CLUSTER_NAME=aks-spot-prod
RESOURCE_GROUP=rg-aks-spot
LOCATION=australiaeast
NAMESPACE=robot-shop

# === Node Pool Names ===
SYSTEM_POOL=system
STANDARD_POOL=stdworkload
SPOT_POOLS=spotgeneral1,spotmemory1,spotgeneral2,spotcompute,spotmemory2

# === VM Sizes, Zones, Priorities, Node Counts ===
# See .env.example for full list of configurable options
```

**All test suites inherit these environment variables automatically.** No need to create separate `.env` files for each test suite.

## Execution Flow

1. **Pre-Flight Checks** (~30s)
   - Verify cluster connectivity
   - Check Azure CLI authentication
   - Capture initial cluster state
   - Start eviction monitor

2. **Sequential Test Execution** (~25-30 minutes)
   - Terratest (Go) - Infrastructure validation
   - Bash Spot Tests - Runtime behavior
   - Python Spot Tests - Pytest framework
   - Continue on failure (run all suites)

3. **Auto-Remediation** (~1-2 minutes)
   - Detect and delete VMSS ghost instances
   - Detect and delete NotReady nodes (stuck >5 min)

4. **Report Generation** (~30 seconds)
   - Stop eviction monitor
   - Capture final cluster state
   - Generate timestamped reports (JSON/HTML/Markdown)

## Report Formats

### JSON Report

Machine-readable format for CI/CD integration:

```
reports/test-report-2026-02-08-143022.json
```

### HTML Report

Interactive dashboard with charts and tables:

```
reports/test-report-2026-02-08-143022.html
```

Open in browser to view:
- Pass/fail summary cards
- Test results table (sortable/filterable)
- Cluster health metrics
- Eviction timeline
- Remediation log

### Markdown Report

GitHub-compatible format for PRs and docs:

```
reports/test-report-2026-02-08-143022.md
```

## Exit Codes

- `0` - All tests passed
- `1` - Some tests failed (orchestrator succeeded)
- `2` - Orchestrator error (pre-flight failed, cluster unreachable)

## Troubleshooting

### Pre-flight Failures

**Cluster unreachable:**
```bash
kubectl cluster-info
kubectl config current-context
```

**Azure CLI not authenticated:**
```bash
az login
az account show
```

### Test Suite Failures

Check individual test suite logs:
```bash
# Terratest
cd ../tests && go test -v ./...

# Bash
cd ../spot-behavior && ./run-all-tests.sh

# Python
cd ../spot-behavior-python && pytest -v
```

### Missing .env File

Create from example:
```bash
cd tests/aks-spot-test-orchestrator
cp .env.example .env
nano .env  # Edit with your cluster details
```

The orchestrator loads this **single .env file** and passes configuration to all test suites.

### Command Not Found After Installation

**Symptom:** After `pip install -e .`, the package appears in `pip list` but running `aks-spot-test` shows "command not found"

**Root Cause:** Bash command hash table cache. If you tried running `aks-spot-test` before installation, bash cached the "command not found" result and continues using it after installation.

**Solutions:**

1. **Clear bash command cache (fastest):**
   ```bash
   hash -r
   aks-spot-test --version
   ```

2. **Open a new terminal:**
   ```bash
   # New terminal automatically clears the hash table
   aks-spot-test --version
   ```

3. **Verify script exists:**
   ```bash
   ls -la ~/.local/bin/aks-spot-test
   which aks-spot-test
   ```

4. **Test with absolute path:**
   ```bash
   ~/.local/bin/aks-spot-test --version
   ```
   If this works but `aks-spot-test` doesn't, it's definitely a hash cache issue (use solution 1 or 2).

5. **Check PATH (if absolute path doesn't work):**
   ```bash
   echo $PATH | grep ~/.local/bin
   ```
   If `~/.local/bin` is missing, add it to your shell config:
   ```bash
   # For bash
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc

   # For zsh
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   ```

6. **Reinstall (if script not created):**
   ```bash
   pip uninstall aks-spot-test -y
   pip install -e .
   ls -la ~/.local/bin/aks-spot-test
   hash -r
   aks-spot-test --version
   ```

## Development

### Package Structure

```
aks_spot_test/
├── __init__.py
├── cli.py                  # CLI interface (Click)
├── orchestrator.py         # Test execution coordinator
├── models.py               # Data models
├── utils.py                # Common utilities
├── runners/                # Test framework runners
│   ├── terratest_runner.py
│   ├── bash_runner.py
│   └── python_runner.py
├── monitors/               # Monitoring modules
│   ├── cluster_state.py
│   └── eviction_rate.py
├── remediators/            # Auto-remediation
│   ├── vmss_ghost.py
│   └── stuck_nodes.py
└── reporters/              # Report generators
    ├── json_reporter.py
    ├── html_reporter.py
    └── markdown_reporter.py
```

### Adding New Features

1. **New Test Framework:**
   - Add runner in `aks_spot_test/runners/`
   - Parse output to `List[TestResult]`
   - Register in `orchestrator.py`

2. **New Remediation:**
   - Add module in `aks_spot_test/remediators/`
   - Return `List[RemediationAction]`
   - Register in `orchestrator.py`

3. **New Report Format:**
   - Add generator in `aks_spot_test/reporters/`
   - Implement `generate_report(report, path)`
   - Register in `orchestrator.py`

## See Also

- **Configuration Guide:** `CONFIGURATION.md` - Detailed configuration reference
- **Design Document:** `docs/plans/2026-02-08-test-orchestrator-design.md`
- **Test Configuration Guide:** `tests/TEST_CONFIGURATION_GUIDE.md`
- **Project Documentation:** `docs/`

## License

Apache 2.0
