"""Main test orchestrator - coordinates all test execution."""

import os
import time
from datetime import datetime
from .models import TestReport
from .monitors import cluster_state, eviction_rate
from .runners import terratest_runner, bash_runner, python_runner
from .remediators import vmss_ghost, stuck_nodes
from .reporters import json_reporter, markdown_reporter, html_reporter
from .utils import get_cluster_name


class TestOrchestrator:
    """Orchestrates test execution, monitoring, and reporting."""

    def __init__(self, config: dict):
        self.config = config
        self.report = TestReport()

        # Load .env file from orchestrator directory
        self._load_environment()

    def _load_environment(self):
        """Load .env file and merge into os.environ."""
        # Look for .env in orchestrator directory
        # __file__ is aks_spot_test/orchestrator.py
        # We need to go up one level to get to aks-spot-test-orchestrator/
        orchestrator_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        env_file = os.path.join(orchestrator_dir, ".env")

        if not os.path.exists(env_file):
            print(f"\n⚠️  No .env file found at {env_file}")
            print(f"ℹ️  Copy .env.example to .env and configure your cluster details")
            print(f"   cd {orchestrator_dir}")
            print(f"   cp .env.example .env\n")
            return

        print(f"Loading configuration from {env_file}")

        loaded_count = 0
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key] = value
                    loaded_count += 1

        print(f"✅ Configuration loaded ({loaded_count} variables)\n")

    def run_all_tests(self) -> TestReport:
        """Execute all test phases and return complete report."""
        start_time = time.time()

        print("\n" + "="*70)
        print("AKS Spot Test Orchestrator")
        print("="*70 + "\n")

        # Phase 1: Pre-flight checks
        print("Phase 1: Pre-flight Checks")
        print("-" * 70)
        if not self._preflight_checks():
            print("❌ Pre-flight checks failed. Aborting.")
            return self.report

        # Phase 2: Test Execution
        print("\nPhase 2: Test Execution")
        print("-" * 70)
        self._run_test_suites()

        # Phase 3: Auto-Remediation
        if self.config.get("remediation", {}).get("enabled", True):
            print("\nPhase 3: Auto-Remediation")
            print("-" * 70)
            self._run_remediation()

        # Phase 4: Report Generation
        print("\nPhase 4: Report Generation")
        print("-" * 70)
        self.report.duration_seconds = time.time() - start_time
        self.report.calculate_summary()
        self._generate_reports()

        print("\n" + "="*70)
        print(f"✅ Test run complete! Duration: {self.report.duration_seconds/60:.1f} minutes")
        print(f"📊 Pass Rate: {self.report.pass_rate:.1f}% ({self.report.passed}/{self.report.total_tests} passed)")
        print("="*70 + "\n")

        return self.report

    def _preflight_checks(self) -> bool:
        """Run pre-flight checks before test execution."""
        print("  Checking cluster connectivity...")
        cluster_name = get_cluster_name()
        if not cluster_name or cluster_name == "unknown":
            print("  ❌ Cannot connect to cluster")
            return False

        self.report.cluster_name = cluster_name
        print(f"  ✅ Connected to cluster: {cluster_name}")

        print("  Capturing initial cluster state...")
        self.report.initial_state = cluster_state.capture_snapshot()
        print(f"  ✅ Snapshot: {self.report.initial_state.total_nodes} nodes, {self.report.initial_state.total_pods} pods")

        print("  Starting eviction monitor...")
        self.eviction_monitor = eviction_rate.EvictionMonitor(
            poll_interval=self.config.get("monitoring", {}).get("eviction_rate", {}).get("poll_interval_seconds", 30)
        )
        self.eviction_monitor.start()
        print("  ✅ Eviction monitor started")

        return True

    def _run_test_suites(self):
        """Run all test suites sequentially."""
        # Terratest
        if self.config.get("test_suites", {}).get("terratest", {}).get("enabled", True):
            print("\n  Running Terratest (Go)...")
            working_dir = self.config.get("test_suites", {}).get("terratest", {}).get("working_dir", "../../")
            timeout = self.config.get("test_suites", {}).get("terratest", {}).get("timeout_minutes", 10)

            results, success = terratest_runner.run_tests(working_dir, timeout)
            self.report.test_results.extend(results)
            status = "✅ PASS" if success else "⚠️ FAIL"
            print(f"  {status} Terratest completed ({len(results)} tests)")

        # Bash tests
        if self.config.get("test_suites", {}).get("bash", {}).get("enabled", True):
            print("\n  Running Bash Spot Tests...")
            working_dir = self.config.get("test_suites", {}).get("bash", {}).get("working_dir", "../../spot-behavior")
            timeout = self.config.get("test_suites", {}).get("bash", {}).get("timeout_minutes", 20)

            results, success = bash_runner.run_tests(working_dir, timeout)
            self.report.test_results.extend(results)
            status = "✅ PASS" if success else "⚠️ FAIL"
            print(f"  {status} Bash tests completed ({len(results)} tests)")

        # Python tests
        if self.config.get("test_suites", {}).get("python", {}).get("enabled", True):
            print("\n  Running Python Spot Tests...")
            working_dir = self.config.get("test_suites", {}).get("python", {}).get("working_dir", "../../spot-behavior-python")
            venv_path = self.config.get("test_suites", {}).get("python", {}).get("venv_path", "venv")
            timeout = self.config.get("test_suites", {}).get("python", {}).get("timeout_minutes", 20)

            results, success = python_runner.run_tests(working_dir, venv_path, timeout)
            self.report.test_results.extend(results)
            status = "✅ PASS" if success else "⚠️ FAIL"
            print(f"  {status} Python tests completed ({len(results)} tests)")

        # Stop eviction monitor
        print("\n  Stopping eviction monitor...")
        events, rate = self.eviction_monitor.stop()
        self.report.eviction_events = events
        self.report.eviction_rate_per_hour = rate
        print(f"  ✅ Eviction rate: {rate:.1f} evictions/hour ({len(events)} total)")

        # Capture final state
        print("  Capturing final cluster state...")
        self.report.final_state = cluster_state.capture_snapshot()
        print(f"  ✅ Final state: {self.report.final_state.total_nodes} nodes, {self.report.final_state.total_pods} pods")

    def _run_remediation(self):
        """Run auto-remediation for infrastructure issues."""
        actions = []

        # VMSS ghost detection
        if self.config.get("remediation", {}).get("vmss_ghosts", {}).get("enabled", True):
            print("  Detecting VMSS ghost instances...")
            # Get cluster config from environment
            resource_group = os.environ.get("RESOURCE_GROUP", "rg-aks-spot")
            cluster_name = self.report.cluster_name
            location = os.environ.get("LOCATION", "australiaeast")
            min_age = self.config.get("remediation", {}).get("vmss_ghosts", {}).get("min_age_minutes", 5)

            ghost_actions = vmss_ghost.detect_and_remediate(resource_group, cluster_name, location, min_age)
            actions.extend(ghost_actions)
            print(f"  ✅ VMSS ghosts: {len(ghost_actions)} instances processed")

        # Stuck node detection
        if self.config.get("remediation", {}).get("stuck_nodes", {}).get("enabled", True):
            print("  Detecting stuck nodes...")
            min_age = self.config.get("remediation", {}).get("stuck_nodes", {}).get("min_age_minutes", 5)

            node_actions = stuck_nodes.detect_and_remediate(min_age)
            actions.extend(node_actions)
            print(f"  ✅ Stuck nodes: {len(node_actions)} nodes processed")

        self.report.remediation_actions = actions
        successful = sum(1 for a in actions if a.success)
        print(f"  ✅ Remediation complete: {successful}/{len(actions)} actions successful")

    def _generate_reports(self):
        """Generate reports in all formats."""
        timestamp_str = self.report.timestamp.strftime("%Y-%m-%d-%H%M%S")
        output_dir = self.config.get("reports", {}).get("output_dir", "./reports")
        os.makedirs(output_dir, exist_ok=True)

        formats = self.config.get("reports", {}).get("formats", ["json", "html", "markdown"])

        if "json" in formats:
            json_path = os.path.join(output_dir, f"test-report-{timestamp_str}.json")
            json_reporter.generate_report(self.report, json_path)
            print(f"  ✅ JSON report: {json_path}")

        if "html" in formats:
            html_path = os.path.join(output_dir, f"test-report-{timestamp_str}.html")
            html_reporter.generate_report(self.report, html_path)
            print(f"  ✅ HTML report: {html_path}")

        if "markdown" in formats:
            md_path = os.path.join(output_dir, f"test-report-{timestamp_str}.md")
            markdown_reporter.generate_report(self.report, md_path)
            print(f"  ✅ Markdown report: {md_path}")
