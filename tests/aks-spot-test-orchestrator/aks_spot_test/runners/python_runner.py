"""Python pytest test runner."""

import os
import time
import json
from typing import List
from ..models import TestResult, Assertion
from ..utils import run_command


def run_tests(working_dir: str, venv_path: str = "venv", timeout_minutes: int = 20) -> tuple[List[TestResult], bool]:
    """Run Python pytest tests and return results.

    Environment variables are inherited from orchestrator's loaded .env file.
    """
    results = []
    start_time = time.time()

    # Check if venv exists and activate
    venv_activate = os.path.join(working_dir, venv_path, "bin", "activate")
    if os.path.exists(venv_activate):
        # Use venv python
        python_cmd = os.path.join(working_dir, venv_path, "bin", "python")
        pytest_cmd = os.path.join(working_dir, venv_path, "bin", "pytest")
    else:
        # Use system python
        python_cmd = "python3"
        pytest_cmd = "pytest"

    # Run pytest with JSON report
    # Environment variables are automatically inherited from os.environ
    result = run_command(
        [pytest_cmd, "-v", "--json-report", "--json-report-file=results.json"],
        cwd=working_dir,
        timeout=timeout_minutes * 60 + 30,
        env=os.environ.copy()
    )

    success = result.returncode == 0

    # Parse pytest JSON report
    results_file = os.path.join(working_dir, "results.json")
    if os.path.exists(results_file):
        try:
            with open(results_file) as f:
                report = json.load(f)

            for test in report.get("tests", []):
                node_id = test.get("nodeid", "")
                outcome = test.get("outcome", "").upper()

                # Map pytest outcomes to our status
                status_map = {
                    "PASSED": "PASS",
                    "FAILED": "FAIL",
                    "SKIPPED": "SKIP",
                    "ERROR": "FAIL"
                }
                status = status_map.get(outcome, "UNKNOWN")

                # Extract test ID and category from nodeid
                # Format: categories/01-pod-distribution/test_file.py::test_name
                parts = node_id.split("::")
                test_name = parts[-1] if parts else node_id

                category = "unknown"
                if "categories/" in node_id:
                    cat_part = node_id.split("categories/")[1]
                    if "/" in cat_part:
                        category = cat_part.split("/")[0]

                # Extract test ID from test name (e.g., test_dist_001 -> DIST-001)
                test_id = test_name

                duration = test.get("duration", 0.0)
                error_msg = None
                if status == "FAIL":
                    call_info = test.get("call", {})
                    error_msg = call_info.get("longrepr", "Test failed")

                results.append(TestResult(
                    test_id=test_id,
                    name=test_name,
                    category=category,
                    framework="python",
                    status=status,
                    duration_seconds=duration,
                    error_message=error_msg
                ))
        except Exception as e:
            # If JSON parsing fails, treat as failure
            results.append(TestResult(
                test_id="python-suite",
                name="Python Test Suite",
                category="runtime",
                framework="python",
                status="FAIL",
                duration_seconds=time.time() - start_time,
                error_message=f"Failed to parse results: {str(e)}"
            ))

    # If no results parsed, create a summary result
    if not results and not success:
        results.append(TestResult(
            test_id="python-suite",
            name="Python Test Suite",
            category="runtime",
            framework="python",
            status="FAIL",
            duration_seconds=time.time() - start_time,
            error_message=result.stderr or "Python tests failed to run"
        ))

    return results, success
