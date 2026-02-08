"""Common utility functions."""

import os
import subprocess
import json
from typing import Any, List, Optional


def run_command(cmd: List[str], cwd: Optional[str] = None, timeout: int = 300, env: Optional[dict] = None) -> subprocess.CompletedProcess:
    """Run shell command and return result.

    Args:
        cmd: Command and arguments as list
        cwd: Working directory for command
        timeout: Timeout in seconds
        env: Environment variables (uses os.environ.copy() if None)

    Returns:
        CompletedProcess instance
    """
    try:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd,
            env=env or os.environ.copy()
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(
            args=cmd,
            returncode=124,
            stdout="",
            stderr=f"Command timed out after {timeout}s"
        )


def run_kubectl(args: List[str], namespace: Optional[str] = None, output_json: bool = False) -> Any:
    """Run kubectl command and optionally parse JSON output."""
    cmd = ["kubectl"] + args
    if namespace:
        cmd += ["-n", namespace]
    if output_json:
        cmd += ["-o", "json"]

    result = run_command(cmd)
    if result.returncode != 0:
        return None

    if output_json:
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return None
    return result.stdout


def run_az(args: List[str], output_json: bool = True) -> Any:
    """Run az CLI command and optionally parse JSON output."""
    cmd = ["az"] + args
    if output_json:
        cmd += ["-o", "json"]

    result = run_command(cmd)
    if result.returncode != 0:
        return None

    if output_json:
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return None
    return result.stdout


def get_cluster_name() -> str:
    """Get current cluster name from kubectl context."""
    result = run_command(["kubectl", "config", "current-context"])
    if result.returncode == 0:
        return result.stdout.strip()
    return "unknown"
