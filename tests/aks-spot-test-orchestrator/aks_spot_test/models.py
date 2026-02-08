"""Data models for test results and reports."""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional
import uuid


@dataclass
class Assertion:
    """Individual assertion within a test."""
    description: str
    expected: Any
    actual: Any
    passed: bool


@dataclass
class TestResult:
    """Single test result from any framework."""
    test_id: str
    name: str
    category: str
    framework: str  # "terratest", "bash", "python"
    status: str  # "PASS", "FAIL", "SKIP"
    duration_seconds: float
    error_message: Optional[str] = None
    assertions: List[Assertion] = field(default_factory=list)
    evidence: Dict[str, Any] = field(default_factory=dict)
    reproduce_commands: List[str] = field(default_factory=list)


@dataclass
class RemediationAction:
    """Auto-remediation action taken."""
    timestamp: datetime
    action_type: str  # "delete_vmss_ghost", "delete_stuck_node"
    target: str
    success: bool
    details: str


@dataclass
class ClusterSnapshot:
    """Cluster state at a point in time."""
    timestamp: datetime
    total_nodes: int
    ready_nodes: int
    spot_nodes: int
    total_pods: int
    pending_pods: int
    node_pool_counts: Dict[str, int] = field(default_factory=dict)


@dataclass
class TestReport:
    """Complete test run report."""
    run_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: datetime = field(default_factory=datetime.now)
    cluster_name: str = ""
    duration_seconds: float = 0.0

    # Summary stats
    total_tests: int = 0
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    pass_rate: float = 0.0

    # Detailed results
    test_results: List[TestResult] = field(default_factory=list)
    framework_summary: Dict[str, Dict] = field(default_factory=dict)
    category_summary: Dict[str, Dict] = field(default_factory=dict)

    # Diagnostics
    initial_state: Optional[ClusterSnapshot] = None
    final_state: Optional[ClusterSnapshot] = None
    eviction_events: List[Dict] = field(default_factory=list)
    eviction_rate_per_hour: float = 0.0
    remediation_actions: List[RemediationAction] = field(default_factory=list)

    # Failure analysis
    top_failures: List[TestResult] = field(default_factory=list)
    failure_patterns: Dict[str, int] = field(default_factory=dict)

    def calculate_summary(self):
        """Calculate summary statistics from test results."""
        self.total_tests = len(self.test_results)
        self.passed = sum(1 for t in self.test_results if t.status == "PASS")
        self.failed = sum(1 for t in self.test_results if t.status == "FAIL")
        self.skipped = sum(1 for t in self.test_results if t.status == "SKIP")
        self.pass_rate = (self.passed / self.total_tests * 100) if self.total_tests > 0 else 0.0

        # Framework summary
        for result in self.test_results:
            if result.framework not in self.framework_summary:
                self.framework_summary[result.framework] = {
                    "total": 0, "passed": 0, "failed": 0, "skipped": 0
                }
            self.framework_summary[result.framework]["total"] += 1
            if result.status == "PASS":
                self.framework_summary[result.framework]["passed"] += 1
            elif result.status == "FAIL":
                self.framework_summary[result.framework]["failed"] += 1
            elif result.status == "SKIP":
                self.framework_summary[result.framework]["skipped"] += 1

        # Category summary
        for result in self.test_results:
            if result.category not in self.category_summary:
                self.category_summary[result.category] = {
                    "total": 0, "passed": 0, "failed": 0, "skipped": 0
                }
            self.category_summary[result.category]["total"] += 1
            if result.status == "PASS":
                self.category_summary[result.category]["passed"] += 1
            elif result.status == "FAIL":
                self.category_summary[result.category]["failed"] += 1
            elif result.status == "SKIP":
                self.category_summary[result.category]["skipped"] += 1

        # Top failures (sorted by category importance)
        failures = [t for t in self.test_results if t.status == "FAIL"]
        self.top_failures = sorted(failures, key=lambda x: x.test_id)[:5]

        # Failure patterns
        for result in failures:
            if result.error_message:
                # Extract first line of error as pattern
                pattern = result.error_message.split('\n')[0][:50]
                self.failure_patterns[pattern] = self.failure_patterns.get(pattern, 0) + 1
