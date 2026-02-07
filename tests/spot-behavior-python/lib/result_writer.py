"""Test result dataclasses and JSON serialization."""

import json
import os
import subprocess
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


@dataclass
class Assertion:
    description: str
    expected: str
    actual: Any
    passed: bool


@dataclass
class TestResult:
    test_id: str
    test_name: str
    category: str
    status: str = "error"  # pass, fail, skip, error
    start_time: str = ""
    end_time: str = ""
    duration_seconds: float = 0.0
    assertions: List[Assertion] = field(default_factory=list)
    evidence: Dict[str, Any] = field(default_factory=dict)
    error_message: str = ""
    environment: Dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> Dict:
        d = asdict(self)
        return d


class ResultWriter:
    """Manages test lifecycle and writes JSON results."""

    def __init__(self, results_dir: str):
        self.results_dir = results_dir
        os.makedirs(results_dir, exist_ok=True)
        self._current: Optional[TestResult] = None
        self._start_ts: float = 0.0

    def start_test(self, test_id: str, test_name: str, category: str) -> TestResult:
        now = datetime.now(timezone.utc)
        self._start_ts = time.time()

        env = {"cluster_name": "", "resource_group": "", "kubernetes_version": ""}
        try:
            r = subprocess.run(["kubectl", "version", "--short"],
                               capture_output=True, text=True, timeout=5)
            if r.returncode == 0:
                env["kubernetes_version"] = r.stdout.strip().split("\n")[0]
        except Exception:
            pass

        self._current = TestResult(
            test_id=test_id,
            test_name=test_name,
            category=category,
            start_time=now.isoformat(),
            environment=env,
        )
        print(f"\n[INFO]  ━━━ {test_id}: {test_name} ━━━")
        return self._current

    def add_assertion(self, desc: str, expected: str, actual: Any, passed: bool):
        a = Assertion(description=desc, expected=expected, actual=actual, passed=passed)
        self._current.assertions.append(a)
        mark = "✓" if passed else "✗"
        print(f"  ➤ {mark} {desc} (expected: {expected}, actual: {actual})")

    def assert_gt(self, desc: str, actual: int, threshold: int):
        self.add_assertion(desc, f">{threshold}", actual, actual > threshold)

    def assert_gte(self, desc: str, actual: int, threshold: int):
        self.add_assertion(desc, f">={threshold}", actual, actual >= threshold)

    def assert_eq(self, desc: str, actual: Any, expected: Any):
        self.add_assertion(desc, str(expected), actual, actual == expected)

    def assert_lt(self, desc: str, actual: int, threshold: int):
        self.add_assertion(desc, f"<{threshold}", actual, actual < threshold)

    def assert_contains(self, desc: str, haystack: str, needle: str):
        found = needle in haystack
        self.add_assertion(desc, f"contains {needle}", "found" if found else "not found", found)

    def assert_not_empty(self, desc: str, value: Any):
        self.add_assertion(desc, "non-empty", f"{len(str(value))} chars", bool(value))

    def add_evidence(self, key: str, value: Any):
        self._current.evidence[key] = value

    def skip_test(self, reason: str):
        self._current.status = "skip"
        self._current.error_message = reason
        self._finish()

    def finish_test(self) -> TestResult:
        if self._current.status == "error" and not self._current.error_message:
            failed = sum(1 for a in self._current.assertions if not a.passed)
            self._current.status = "pass" if failed == 0 else "fail"
        self._finish()
        return self._current

    def _finish(self):
        now = datetime.now(timezone.utc)
        self._current.end_time = now.isoformat()
        self._current.duration_seconds = round(time.time() - self._start_ts, 1)

        out_path = os.path.join(self.results_dir, f"{self._current.test_id}.json")
        with open(out_path, "w") as f:
            json.dump(self._current.to_dict(), f, indent=2, default=str)

        status = self._current.status
        dur = self._current.duration_seconds
        tid = self._current.test_id
        if status == "pass":
            print(f"[INFO]  ✓ {tid} PASSED ({dur}s)")
        elif status == "fail":
            print(f"[ERROR] ✗ {tid} FAILED ({dur}s)")
        elif status == "skip":
            print(f"[WARN]  ⊘ {tid} SKIPPED: {self._current.error_message}")
        else:
            print(f"[ERROR] ! {tid} ERROR: {self._current.error_message}")


def aggregate_results(results_dir: str) -> Dict:
    """Read all individual result files and produce a summary."""
    run_id = f"run-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    results = []
    categories: Dict[str, Dict] = {}
    failed_tests = []

    for fname in sorted(os.listdir(results_dir)):
        if not fname.endswith(".json") or fname.startswith("summary-"):
            continue
        with open(os.path.join(results_dir, fname)) as f:
            result = json.load(f)
        results.append(result)

        cat = result.get("category", "unknown")
        if cat not in categories:
            categories[cat] = {"name": cat, "total": 0, "passed": 0, "failed": 0, "skipped": 0}
        categories[cat]["total"] += 1

        status = result.get("status", "error")
        if status == "pass":
            categories[cat]["passed"] += 1
        elif status == "fail":
            categories[cat]["failed"] += 1
            failed_tests.append({
                "test_id": result["test_id"],
                "error_message": result.get("error_message", "")
            })
        elif status == "skip":
            categories[cat]["skipped"] += 1

    total = len(results)
    passed = sum(1 for r in results if r["status"] == "pass")
    failed = sum(1 for r in results if r["status"] == "fail")
    skipped = sum(1 for r in results if r["status"] == "skip")
    rate = f"{(passed / total * 100):.1f}%" if total > 0 else "0.0%"

    summary = {
        "run_id": run_id,
        "total_tests": total,
        "passed": passed,
        "failed": failed,
        "skipped": skipped,
        "pass_rate": rate,
        "categories": list(categories.values()),
        "failed_tests": failed_tests,
        "results": results,
    }

    out_path = os.path.join(results_dir, f"summary-{run_id}.json")
    with open(out_path, "w") as f:
        json.dump(summary, f, indent=2, default=str)

    print(f"\n{'═' * 51}")
    print(f"  Run Summary: {run_id}")
    print(f"  Total: {total}  Pass: {passed}  Fail: {failed}  Skip: {skipped}")
    print(f"  Pass Rate: {rate}")
    print(f"{'═' * 51}")

    if failed_tests:
        print("\nFailed tests:")
        for ft in failed_tests:
            print(f"  ✗ {ft['test_id']}: {ft['error_message']}")

    print(f"\nResults saved to: {out_path}")
    return summary
