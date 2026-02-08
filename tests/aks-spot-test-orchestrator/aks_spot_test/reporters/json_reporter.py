"""JSON report generator."""

import json
from dataclasses import asdict
from datetime import datetime
from ..models import TestReport


def generate_report(report: TestReport, output_path: str):
    """Generate JSON report file."""
    # Convert dataclass to dict
    report_dict = asdict(report)

    # Convert datetime objects to ISO format strings
    def convert_datetime(obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        elif isinstance(obj, dict):
            return {k: convert_datetime(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [convert_datetime(item) for item in obj]
        return obj

    report_dict = convert_datetime(report_dict)

    # Write JSON file
    with open(output_path, 'w') as f:
        json.dump(report_dict, f, indent=2)
