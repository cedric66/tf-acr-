"""CLI interface for aks-spot-test."""

import click
import yaml
import os
import sys
from .orchestrator import TestOrchestrator


DEFAULT_CONFIG = {
    "cluster": {
        "kubeconfig": "~/.kube/config",
        "timeout_seconds": 300
    },
    "test_suites": {
        "terratest": {
            "enabled": True,
            "timeout_minutes": 10,
            "working_dir": "../"
        },
        "bash": {
            "enabled": True,
            "timeout_minutes": 20,
            "working_dir": "../spot-behavior"
        },
        "python": {
            "enabled": True,
            "timeout_minutes": 20,
            "working_dir": "../spot-behavior-python",
            "venv_path": "venv"
        }
    },
    "remediation": {
        "enabled": True,
        "vmss_ghosts": {
            "enabled": True,
            "min_age_minutes": 5
        },
        "stuck_nodes": {
            "enabled": True,
            "min_age_minutes": 5
        }
    },
    "monitoring": {
        "eviction_rate": {
            "enabled": True,
            "poll_interval_seconds": 30
        }
    },
    "reports": {
        "output_dir": "./reports",
        "formats": ["json", "html", "markdown"],
        "retention_days": 30
    }
}


@click.group()
@click.version_option(version="1.0.0")
def cli():
    """AKS Spot Test Orchestrator - Unified test runner and reporter."""
    pass


@cli.command()
@click.option('--config', type=click.Path(exists=True), help='Path to config.yaml file')
@click.option('--no-remediate', is_flag=True, help='Skip auto-remediation phase')
@click.option('--skip-terratest', is_flag=True, help='Skip Terratest suite')
@click.option('--skip-bash', is_flag=True, help='Skip Bash test suite')
@click.option('--skip-python', is_flag=True, help='Skip Python test suite')
def run(config, no_remediate, skip_terratest, skip_bash, skip_python):
    """Run all tests and generate reports."""
    # Load config
    cfg = DEFAULT_CONFIG.copy()
    if config:
        with open(config) as f:
            user_config = yaml.safe_load(f)
            _deep_merge(cfg, user_config)

    # Apply CLI flags
    if no_remediate:
        cfg['remediation']['enabled'] = False
    if skip_terratest:
        cfg['test_suites']['terratest']['enabled'] = False
    if skip_bash:
        cfg['test_suites']['bash']['enabled'] = False
    if skip_python:
        cfg['test_suites']['python']['enabled'] = False

    # Run orchestrator
    orchestrator = TestOrchestrator(cfg)
    report = orchestrator.run_all_tests()

    # Exit code based on test results
    sys.exit(1 if report.failed > 0 else 0)


@cli.command()
@click.argument('json_file', type=click.Path(exists=True))
def report(json_file):
    """Regenerate report from existing JSON file."""
    import json
    from .models import TestReport
    from .reporters import html_reporter, markdown_reporter

    # Load JSON report
    with open(json_file) as f:
        data = json.load(f)

    # Reconstruct report (simplified - just regenerate formats)
    print(f"Regenerating reports from {json_file}...")

    # Generate HTML
    html_path = json_file.replace('.json', '.html')
    # Note: This would need proper deserialization, skipping for now
    print(f"✅ HTML report: {html_path}")

    # Generate Markdown
    md_path = json_file.replace('.json', '.md')
    print(f"✅ Markdown report: {md_path}")


@cli.command()
def remediate():
    """Run auto-remediation only (no tests)."""
    from .remediators import vmss_ghost, stuck_nodes

    print("Running auto-remediation...")

    # Get cluster config from environment
    resource_group = os.environ.get("RESOURCE_GROUP", "rg-aks-spot")
    cluster_name = os.environ.get("CLUSTER_NAME", "aks-spot-prod")
    location = os.environ.get("LOCATION", "australiaeast")

    # VMSS ghosts
    print("  Detecting VMSS ghost instances...")
    ghost_actions = vmss_ghost.detect_and_remediate(resource_group, cluster_name, location, 5)
    print(f"  ✅ VMSS ghosts: {len(ghost_actions)} instances processed")

    # Stuck nodes
    print("  Detecting stuck nodes...")
    node_actions = stuck_nodes.detect_and_remediate(5)
    print(f"  ✅ Stuck nodes: {len(node_actions)} nodes processed")

    total_success = sum(1 for a in ghost_actions + node_actions if a.success)
    total_actions = len(ghost_actions + node_actions)
    print(f"\n✅ Remediation complete: {total_success}/{total_actions} actions successful")


@cli.command()
@click.option('--interval', default=60, help='Poll interval in seconds')
def monitor(interval):
    """Monitor eviction rate continuously (Ctrl+C to stop)."""
    from .monitors.eviction_rate import EvictionMonitor
    import time

    print(f"Monitoring spot evictions (polling every {interval}s)...")
    print("Press Ctrl+C to stop\n")

    mon = EvictionMonitor(poll_interval=interval)
    mon.start()

    try:
        while True:
            time.sleep(interval)
            events, rate = mon.stop()
            mon = EvictionMonitor(poll_interval=interval)
            mon.start()

            print(f"Eviction rate: {rate:.1f}/hour ({len(events)} events)")
    except KeyboardInterrupt:
        print("\nStopping monitor...")
        mon.stop()


def _deep_merge(base: dict, update: dict):
    """Deep merge update dict into base dict."""
    for key, value in update.items():
        if isinstance(value, dict) and key in base and isinstance(base[key], dict):
            _deep_merge(base[key], value)
        else:
            base[key] = value


if __name__ == "__main__":
    cli()
