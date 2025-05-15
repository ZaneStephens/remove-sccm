# SCCM Client Removal Script

## Overview
This PowerShell script provides a robust solution for completely removing the System Center Configuration Manager (SCCM) client from a Windows system. The script starts with a standard uninstall attempt and then meticulously cleans up services, WMI namespaces, registry entries, and files, all while keeping you informed with detailed logs.

## Why Use This Script?
Manually removing the SCCM client can be tedious and error-prone due to its deep integration with Windows. This script automates the process, handling edge cases and potential failures gracefully. It’s built with safety in mind, offering options to preview or confirm actions, making it suitable for both one-off use and deployment in managed environments.

## How It Works
The script operates in a structured sequence:
- Attempts a standard uninstall using the SCCM-provided `ccmsetup.exe /uninstall`.
- Stops and deletes SCCM-related services, ensuring they’re fully terminated.
- Cleans up SCCM-specific WMI namespaces for a thorough removal.
- Removes associated registry keys and file system artifacts, like installation directories and cache.
- Logs every step with timestamps and severity levels for easy tracking and troubleshooting.

It also checks for administrative privileges to ensure it can perform all necessary actions without interruption.

## Getting Started
To use the script effectively, follow these steps:

1. **Run as Administrator**: Launch PowerShell with elevated privileges, as the script modifies system-level components.
2. **Execute the Script**: Navigate to the script’s directory and run it with:
   ```powershell
   .\remove-sccmagent.ps1
   ```
3. **Preview Actions (Optional)**: Add the `-WhatIf` switch to see what the script will do without making changes:
   ```powershell
   .\remove-sccmagent.ps1 -WhatIf
   ```
4. **Confirm Actions (Optional)**: Use the `-Confirm` switch to approve each step manually:
   ```powershell
   .\remove-sccmagent.ps1 -Confirm
   ```
5. **Review Output**: Check the console for detailed logs to verify what was done or diagnose issues.

## Tips and Precautions
- **Backup First**: Since the script makes significant system changes, back up critical data beforehand.
- **Reboot After**: A restart may be needed to fully apply all changes.
- **Test It Out**: Try it in a lab environment first to understand its impact on your systems.

This script is designed to be both powerful and user-friendly, giving you confidence in managing SCCM client removals.
