"""Bash spot behavior test runner."""

import os
import time
import json
import glob
from typing import List
from ..models import TestResult, Assertion
from ..utils import run_command


def run_tests(working_dir: str, timeout_minutes: int = 20) -> tuple[List[TestResult], bool]:
    """Run bash spot behavior tests and return results.

    Environment variables are inherited from orchestrator's loaded .env file.
    """
    results = []
    start_time = time.time()

    # Run all tests
    # Environment variables are automatically inherited from os.environ
    result = run_command(
        ["./run-all-tests.sh"],
        cwd=working_dir,
        timeout=timeout_minutes * 60 + 30,
        env=os.environ.copy()
    )

    success = result.returncode == 0

    # Parse JSON results from results/*.json
    results_dir = os.path.join(working_dir, "results")
    if os.path.exists(results_dir):
        for json_file in glob.glob(os.path.join(results_dir, "*.json")):
            try:
                with open(json_file) as f:
                    test_data = json.load(f)

                    test_id = test_data.get("test_id", "")
                    test_name = test_data.get("test_name", "")
                    category = test_data.get("category", "")
                    status = test_data.get("status", "UNKNOWN")
                    duration = test_data.get("duration_seconds", 0.0)
                    error_msg = test_data.get("error_message")

                    # Parse assertions
                    assertions = []
                    for assertion in test_data.get("assertions", []):
                        assertions.append(Assertion(
                            description=assertion.get("description", ""),
                            expected=assertion.get("expected"),
                            actual=assertion.get("actual"),
                            passed=assertion.get("passed", False)
                        ))

                    # Extract reproduce commands
                    evidence = test_data.get("evidence", {})
                    reproduce_cmds = test_data.get("reproduce_commands", [])

                    results.append(TestResult(
                        test_id=test_id,
                        name=test_name,
                        category=category,
                        framework="bash",
                        status=status,
                        duration_seconds=duration,
                        error_message=error_msg,
                        assertions=assertions,
                        evidence=evidence,
                        reproduce_commands=reproduce_cmds
                    ))
            except Exception as e:
                # Skip malformed JSON files
                continue

    # If no results parsed, create a summary result
    if not results and not success:
        results.append(TestResult(
            test_id="bash-suite",
            name="Bash Test Suite",
            category="runtime",
            framework="bash",
            status="FAIL",
            duration_seconds=time.time() - start_time,
            error_message=result.stderr or "Bash tests failed to run"
        ))

    return results, success
