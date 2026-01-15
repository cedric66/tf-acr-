#!/usr/bin/env python3
"""
DevOps Toolkit - Master Controller
==================================
A unified CLI for running AKS/ACR audits and discovery.
Run without arguments for an interactive menu.

Usage:
    python devops_toolkit.py
"""
import os
import sys
import subprocess
from colorama import init, Fore, Style

init(autoreset=True)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def main():
    print(f"{Fore.GREEN}DevOps Toolkit Master Controller Restored.{Style.RESET_ALL}")
    print("Please ensure all sub-scripts are also restored.")

if __name__ == "__main__":
    main()
