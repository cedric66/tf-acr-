"""Setup script for aks-spot-test package."""

from setuptools import setup, find_packages

setup(
    name="aks-spot-test",
    version="1.0.0",
    description="AKS Spot Test Orchestrator - Unified test runner and reporter",
    author="AKS Spot Optimization Team",
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        "click>=8.0.0",
        "pyyaml>=6.0",
    ],
    entry_points={
        "console_scripts": [
            "aks-spot-test=aks_spot_test.cli:cli",
        ],
    },
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Testing",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
)
