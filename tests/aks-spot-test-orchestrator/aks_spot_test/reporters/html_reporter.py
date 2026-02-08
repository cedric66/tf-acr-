"""HTML report generator."""

import os
from ..models import TestReport


def generate_report(report: TestReport, output_path: str):
    """Generate HTML report file."""
    template = _get_html_template()

    # Replace placeholders
    html = template.replace("{{CLUSTER_NAME}}", report.cluster_name)
    html = html.replace("{{TIMESTAMP}}", report.timestamp.strftime('%Y-%m-%d %H:%M:%S'))
    html = html.replace("{{DURATION}}", _format_duration(report.duration_seconds))
    html = html.replace("{{PASS_RATE}}", f"{report.pass_rate:.1f}")
    html = html.replace("{{TOTAL_TESTS}}", str(report.total_tests))
    html = html.replace("{{PASSED}}", str(report.passed))
    html = html.replace("{{FAILED}}", str(report.failed))
    html = html.replace("{{SKIPPED}}", str(report.skipped))
    html = html.replace("{{EVICTION_RATE}}", f"{report.eviction_rate_per_hour:.1f}")
    html = html.replace("{{REMEDIATION_COUNT}}", str(len(report.remediation_actions)))

    # Build test results table
    results_html = ""
    for result in report.test_results:
        status_class = "success" if result.status == "PASS" else "danger" if result.status == "FAIL" else "warning"
        status_icon = "✅" if result.status == "PASS" else "❌" if result.status == "FAIL" else "⏭️"

        results_html += f"""
        <tr class="table-{status_class}">
            <td>{status_icon} {result.test_id}</td>
            <td>{result.name}</td>
            <td>{result.framework}</td>
            <td>{result.category}</td>
            <td>{result.duration_seconds:.1f}s</td>
        </tr>
        """

    html = html.replace("{{TEST_RESULTS}}", results_html)

    # Write file
    with open(output_path, 'w') as f:
        f.write(html)


def _format_duration(seconds: float) -> str:
    """Format duration in human-readable form."""
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{minutes}m {secs}s"


def _get_html_template() -> str:
    """Get minimal HTML template."""
    return """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AKS Spot Test Report</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { padding: 20px; }
        .stat-card { margin-bottom: 20px; }
        .badge-custom { font-size: 1.2em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>AKS Spot Test Report</h1>
        <p class="text-muted">
            <strong>Cluster:</strong> {{CLUSTER_NAME}} |
            <strong>Date:</strong> {{TIMESTAMP}} |
            <strong>Duration:</strong> {{DURATION}}
        </p>
        <hr>

        <!-- Summary Cards -->
        <div class="row">
            <div class="col-md-3">
                <div class="card stat-card">
                    <div class="card-body">
                        <h5 class="card-title">Pass Rate</h5>
                        <h2>{{PASS_RATE}}%</h2>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card stat-card">
                    <div class="card-body">
                        <h5 class="card-title">Total Tests</h5>
                        <h2>{{TOTAL_TESTS}}</h2>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card stat-card">
                    <div class="card-body">
                        <h5 class="card-title">Eviction Rate</h5>
                        <h2>{{EVICTION_RATE}}/hr</h2>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card stat-card">
                    <div class="card-body">
                        <h5 class="card-title">Remediations</h5>
                        <h2>{{REMEDIATION_COUNT}}</h2>
                    </div>
                </div>
            </div>
        </div>

        <!-- Test Summary -->
        <div class="row mt-4">
            <div class="col-md-12">
                <h3>Test Summary</h3>
                <p>
                    <span class="badge bg-success badge-custom">✅ {{PASSED}} Passed</span>
                    <span class="badge bg-danger badge-custom">❌ {{FAILED}} Failed</span>
                    <span class="badge bg-warning badge-custom">⏭️ {{SKIPPED}} Skipped</span>
                </p>
            </div>
        </div>

        <!-- Test Results Table -->
        <div class="row mt-4">
            <div class="col-md-12">
                <h3>Test Results</h3>
                <table class="table table-striped table-hover">
                    <thead>
                        <tr>
                            <th>Test ID</th>
                            <th>Name</th>
                            <th>Framework</th>
                            <th>Category</th>
                            <th>Duration</th>
                        </tr>
                    </thead>
                    <tbody>
                        {{TEST_RESULTS}}
                    </tbody>
                </table>
            </div>
        </div>

        <footer class="mt-5 text-center text-muted">
            <p>Generated by <code>aks-spot-test</code> v1.0.0</p>
        </footer>
    </div>
</body>
</html>
"""
