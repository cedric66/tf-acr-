"""Terratest (Go) test runner."""

import os
import time
from typing import List
from ..models import TestResult
from ..utils import run_command


def run_tests(working_dir: str, timeout_minutes: int = 10) -> tuple[List[TestResult], bool]:
    """Run Terratest (Go) tests and return results.

    Environment variables are inherited from orchestrator's loaded .env file.
    """
    results = []
    start_time = time.time()

    # Run go test with JSON output
    # Environment variables are automatically inherited from os.environ
    result = run_command(
        ["go", "test", "-v", "-timeout", f"{timeout_minutes}m", "-json", "./..."],
        cwd=working_dir,
        timeout=timeout_minutes * 60 + 30,
        env=os.environ.copy()
    )

    success = result.returncode == 0

    # Parse go test JSON output
    if result.stdout:
        for line in result.stdout.split('\n'):
            line = line.strip()
            if not line:
                continue
            try:
                import json
                event = json.loads(line)
                action = event.get("Action")
                test_name = event.get("Test", "")

                if action == "pass" and test_name:
                    results.append(TestResult(
                        test_id=test_name,
                        name=test_name,
                        category="infrastructure",
                        framework="terratest",
                        status="PASS",
                        duration_seconds=event.get("Elapsed", 0.0)
                    ))
                elif action == "fail" and test_name:
                    results.append(TestResult(
                        test_id=test_name,
                        name=test_name,
                        category="infrastructure",
                        framework="terratest",
                        status="FAIL",
                        duration_seconds=event.get("Elapsed", 0.0),
                        error_message=event.get("Output", "Test failed")
                    ))
                elif action == "skip" and test_name:
                    results.append(TestResult(
                        test_id=test_name,
                        name=test_name,
                        category="infrastructure",
                        framework="terratest",
                        status="SKIP",
                        duration_seconds=event.get("Elapsed", 0.0)
                    ))
            except:
                continue

    # If no results parsed, create a summary result
    if not results and not success:
        results.append(TestResult(
            test_id="terratest-suite",
            name="Terratest Suite",
            category="infrastructure",
            framework="terratest",
            status="FAIL",
            duration_seconds=time.time() - start_time,
            error_message=result.stderr or "Terratest failed to run"
        ))

    return results, success
