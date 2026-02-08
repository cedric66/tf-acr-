# AKS Spot Behavior Tests (Python)

Python implementation of the AKS spot behavior test suite with pytest framework and structured output.

## Overview

This is a **Python/pytest port** of the bash test suite (`../spot-behavior/`), providing:
- Pytest framework with fixtures and parametrization
- Better IDE integration and debugging
- Type hints and structured code
- Same test coverage as bash version (50+ tests across 10 categories)

## Prerequisites

1. **Python 3.8+**
   ```bash
   python3 --version
   ```

2. **Deployed AKS cluster** with spot node pools
3. **kubectl** configured to connect to the cluster
4. **Azure CLI** (for VMSS tests)
5. **Robot Shop** deployed:
   ```bash
   kubectl apply -f ../../manifests/robot-shop/
   ```

## Installation

### Create Virtual Environment

```bash
cd tests/spot-behavior-python
python3 -m venv venv
source venv/bin/activate  # Linux/Mac
# OR
venv\Scripts\activate  # Windows
```

### Install Dependencies

```bash
pip install -r requirements.txt
```

**Required packages:**
- `pytest>=7.4.0`
- `kubernetes>=28.0.0`
- `azure-mgmt-compute>=30.0.0`
- `azure-identity>=1.14.0`

## Configuration

### Step 1: Create Configuration File

```bash
cp .env.example .env
```

### Step 2: Edit .env

```bash
# Match these to your deployed cluster
CLUSTER_NAME=aks-spot-prod
RESOURCE_GROUP=rg-aks-spot
NAMESPACE=robot-shop
```

### Step 3: Load Configuration

```bash
export $(cat .env | xargs)
```

## Running Tests

### Run All Tests

```bash
pytest -v
```

### Run Specific Category

```bash
# Pod distribution tests (read-only, safe)
pytest -v categories/test_01_pod_distribution.py

# Eviction behavior tests (destructive)
pytest -v categories/test_02_eviction_behavior.py
```

### Run Single Test

```bash
pytest -v categories/test_01_pod_distribution.py::TestPodDistribution::test_DIST_001_pods_on_spot_nodes
```

### Run Tests Matching Pattern

```bash
# Run all PDB tests
pytest -v -k "pdb"

# Run all eviction tests
pytest -v -k "evict"
```

### Generate HTML Report

```bash
pytest --html=report.html --self-contained-html
```

### Parallel Execution

```bash
pip install pytest-xdist
pytest -v -n auto  # Auto-detect CPU count
```

## Test Categories

| Category | Module | Tests | Type |
|----------|--------|-------|------|
| Pod Distribution | `test_01_pod_distribution.py` | 10 | Read-only |
| Eviction Behavior | `test_02_eviction_behavior.py` | 10 | Destructive |
| PDB Enforcement | `test_03_pdb_enforcement.py` | 6 | Destructive |
| Topology Spread | `test_04_topology_spread.py` | 5 | Destructive |
| Recovery | `test_05_recovery_rescheduling.py` | 6 | Destructive |
| Sticky Fallback | `test_06_sticky_fallback.py` | 5 | Destructive |
| VMSS/Node Pool | `test_07_vmss_node_pool.py` | 6 | Read-only |
| Autoscaler | `test_08_autoscaler.py` | 5 | Mixed |
| Cross-Service | `test_09_cross_service.py` | 5 | Destructive |
| Edge Cases | `test_10_edge_cases.py` | 5 | Destructive |

**⚠️ WARNING**: Destructive tests drain nodes and may temporarily disrupt workloads. Run in non-production or during maintenance windows.

## Configuration Options

Configuration is loaded from environment variables via `config.py`:

```python
from config import TestConfig

config = TestConfig()
print(config.cluster_name)  # From CLUSTER_NAME env var or default
```

### Available Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `aks-spot-prod` | AKS cluster name |
| `RESOURCE_GROUP` | `rg-aks-spot` | Azure resource group |
| `NAMESPACE` | `robot-shop` | Kubernetes namespace for test workloads |
| `RESULTS_DIR` | `./results` | Directory for JSON test results |

### Multiple Cluster Configs

```bash
# Dev cluster
echo "CLUSTER_NAME=aks-dev" > .env.dev
echo "RESOURCE_GROUP=rg-dev" >> .env.dev

# Prod cluster
echo "CLUSTER_NAME=aks-prod" > .env.prod
echo "RESOURCE_GROUP=rg-prod" >> .env.prod

# Run against dev
export $(cat .env.dev | xargs)
pytest -v

# Run against prod
export $(cat .env.prod | xargs)
pytest -v
```

## Results

### JSON Output

Test results are written to `results/` directory in JSON format:

```bash
ls results/
# DIST-001.json  DIST-002.json  ...
```

### Pytest Output

```bash
# Verbose output with test names
pytest -v

# Show print statements
pytest -v -s

# Show slowest 10 tests
pytest --durations=10
```

### Custom Markers

```bash
# Run only read-only tests
pytest -v -m "readonly"

# Skip destructive tests
pytest -v -m "not destructive"
```

**Note**: Markers need to be defined in `pytest.ini` or `pyproject.toml`.

## CI/CD Integration

### GitHub Actions

```yaml
name: Spot Behavior Tests (Python)

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - uses: azure/aks-set-context@v3
        with:
          resource-group: ${{ secrets.AKS_RESOURCE_GROUP }}
          cluster-name: ${{ secrets.AKS_CLUSTER_NAME }}

      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          cd tests/spot-behavior-python
          pip install -r requirements.txt

      - name: Run read-only tests
        env:
          CLUSTER_NAME: ${{ secrets.AKS_CLUSTER_NAME }}
          RESOURCE_GROUP: ${{ secrets.AKS_RESOURCE_GROUP }}
        run: |
          cd tests/spot-behavior-python
          pytest -v categories/test_01_pod_distribution.py categories/test_07_vmss_node_pool.py
```

## Development

### Project Structure

```
spot-behavior-python/
├── run_all_tests.py           # Test runner script
├── config.py                  # Configuration loader (reads env vars)
├── .env.example               # Configuration template
├── .env                       # Your local config (DO NOT COMMIT)
├── requirements.txt           # Python dependencies
├── lib/
│   ├── __init__.py
│   ├── test_helpers.py        # kubectl/az wrappers, assertions
│   └── result_writer.py       # JSON result writer
├── categories/
│   ├── __init__.py
│   ├── test_01_pod_distribution.py
│   ├── test_02_eviction_behavior.py
│   ├── test_03_pdb_enforcement.py
│   ├── test_04_topology_spread.py
│   ├── test_05_recovery_rescheduling.py
│   ├── test_06_sticky_fallback.py
│   ├── test_07_vmss_node_pool.py
│   ├── test_08_autoscaler.py
│   ├── test_09_cross_service.py
│   └── test_10_edge_cases.py
└── results/                   # JSON test results (gitignored)
```

### Writing New Tests

```python
from lib.test_helpers import get_spot_nodes, is_pod_on_spot
from config import TestConfig

def test_my_custom_test():
    config = TestConfig()
    spot_nodes = get_spot_nodes(config.namespace)
    assert len(spot_nodes) > 0, "No spot nodes found"
```

### Type Checking

```bash
pip install mypy
mypy categories/
```

### Linting

```bash
pip install ruff
ruff check .
```

## Troubleshooting

### ModuleNotFoundError

```bash
# Ensure you're in venv
source venv/bin/activate

# Reinstall dependencies
pip install -r requirements.txt
```

### Kubernetes Connection Error

```bash
# Verify kubectl context
kubectl cluster-info

# Get AKS credentials
az aks get-credentials --resource-group <rg> --name <cluster>
```

### "No pods found"

```bash
# Verify Robot Shop is deployed
kubectl get pods -n robot-shop

# Deploy if missing
kubectl apply -f ../../manifests/robot-shop/
```

### Azure Auth Errors (VMSS tests)

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription <subscription-id>
```

## Comparison: Bash vs Python

| Feature | Bash (`../spot-behavior/`) | Python (this) |
|---------|---------------------------|---------------|
| **Framework** | Custom bash + jq | pytest |
| **IDE Support** | Limited | Full (autocomplete, debugging) |
| **Type Safety** | None | Type hints |
| **Parallel Execution** | Manual | `pytest-xdist` |
| **Fixtures** | Manual setup/teardown | pytest fixtures |
| **Speed** | Fast (no startup overhead) | Slower (Python interpreter) |
| **Debugging** | `set -x`, `echo` | `pdb`, IDE debugger |
| **Dependencies** | bash, jq, kubectl, az | Python packages |

**Recommendation**: Use bash for quick CI checks, Python for development and detailed debugging.

## Related Documentation

- **Bash Test Suite**: See `../spot-behavior/README.md`
- **Project Overview**: See `../../CONSOLIDATED_PROJECT_BRIEF.md`
- **Spot Eviction Scenarios**: See `../../docs/SPOT_EVICITION_SCENARIOS.md`
- **Terratest Suite**: See `../README.md` (Go-based infrastructure tests)
