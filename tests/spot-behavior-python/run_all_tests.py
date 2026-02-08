#!/usr/bin/env python3
"""Entry point for AKS spot behavior tests (Python version).

Setup:
    1. Copy .env.example to .env
    2. Edit .env with your cluster details (CLUSTER_NAME, RESOURCE_GROUP, NAMESPACE)
    3. Load: export $(cat .env | xargs)
    4. Run tests (see usage below)
    See README.md for detailed setup instructions

Usage:
    python run_all_tests.py                          # Run all tests
    python run_all_tests.py --category pod-dist      # Run one category
    python run_all_tests.py --test DIST-001          # Run one test
    python run_all_tests.py --dry-run                # List tests without executing
"""

import argparse
import importlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import TestConfig
from lib.result_writer import ResultWriter, aggregate_results

# Category module mapping
CATEGORY_MODULES = {
    "01-pod-distribution": "categories.test_01_pod_distribution",
    "02-eviction-behavior": "categories.test_02_eviction_behavior",
    "03-pdb-enforcement": "categories.test_03_pdb_enforcement",
    "04-topology-spread": "categories.test_04_topology_spread",
    "05-recovery-rescheduling": "categories.test_05_recovery_rescheduling",
    "06-sticky-fallback": "categories.test_06_sticky_fallback",
    "07-vmss-node-pool": "categories.test_07_vmss_node_pool",
    "08-autoscaler": "categories.test_08_autoscaler",
    "09-cross-service": "categories.test_09_cross_service",
    "10-edge-cases": "categories.test_10_edge_cases",
}


def discover_tests(category_filter: str = "", test_filter: str = ""):
    """Discover test functions across category modules."""
    tests = []
    for cat_key, module_name in sorted(CATEGORY_MODULES.items()):
        if category_filter and category_filter not in cat_key:
            continue
        try:
            mod = importlib.import_module(module_name)
        except ImportError as e:
            print(f"[WARN] Cannot import {module_name}: {e}")
            continue

        for attr_name in sorted(dir(mod)):
            if not attr_name.startswith("test_"):
                continue
            func = getattr(mod, attr_name)
            if not callable(func):
                continue
            test_id = getattr(func, "test_id", attr_name)
            if test_filter and test_filter not in test_id and test_filter not in attr_name:
                continue
            tests.append((cat_key, test_id, attr_name, func))
    return tests


def main():
    parser = argparse.ArgumentParser(description="AKS Spot Behavior Tests")
    parser.add_argument("--category", default="", help="Filter by category name")
    parser.add_argument("--test", default="", help="Filter by test ID (e.g. DIST-001)")
    parser.add_argument("--dry-run", action="store_true", help="List tests without executing")
    args = parser.parse_args()

    config = TestConfig()
    writer = ResultWriter(config.results_dir)

    # Clear previous results unless running a single test
    if not args.test and not args.dry_run:
        for f in os.listdir(config.results_dir):
            if f.endswith(".json"):
                os.remove(os.path.join(config.results_dir, f))

    tests = discover_tests(args.category, args.test)
    if not tests:
        print(f"No tests found (category={args.category}, test={args.test})")
        sys.exit(1)

    print(f"Found {len(tests)} test(s) to execute\n")

    for cat_key, test_id, func_name, func in tests:
        if args.dry_run:
            print(f"[DRY-RUN] {test_id} ({cat_key}/{func_name})")
            continue

        print(f"\n{'═' * 51}")
        print(f"  Executing: {test_id} ({func_name})")
        print(f"{'═' * 51}")

        try:
            func(config, writer)
        except Exception as e:
            print(f"[ERROR] {test_id} raised exception: {e}")

    if not args.dry_run:
        aggregate_results(config.results_dir)


if __name__ == "__main__":
    main()
