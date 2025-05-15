# SCCM Client Removal Script: Enhancements Explained

The provided PowerShell script for removing the SCCM client has been revised to incorporate several improvements focusing on robustness, error handling, logging, and modern PowerShell practices. Here's a breakdown of the key changes:

## Script Structure and Best Practices:
- **CmdletBinding and SupportsShouldProcess**: Added `[CmdletBinding(SupportsShouldProcess = $true)]` to enable common parameters like `-Verbose`, `-Debug`, and importantly, `-Confirm` and `-WhatIf`. This allows for safer execution by previewing changes before they are made.
- **Administrator Check**: The script now explicitly checks if it's running with Administrator privileges and exits if not.
- **BEGIN, PROCESS, END Blocks**: The script is structured into `begin`, `process`, and `end` blocks for better organization and initialization/cleanup tasks.
- **Logging Function (Write-Log)**: A custom `Write-Log` function is introduced to standardize log messages with timestamps and severity levels (INFO, WARN, ERROR). This makes the script's output much clearer.
- **Comments**: Added more detailed comments explaining each section and its purpose.

## Graceful Uninstall Improvement:
- **Path Construction**: Used `Join-Path` for constructing `$CcmSetupPath` which is more robust than string concatenation.
- **Process Handling**: `Start-Process` now uses `-PassThru` to get the process object, allowing for checking the `ExitCode` of the uninstaller.
- **ErrorAction**: Maintained `ErrorAction SilentlyContinue` for `Start-Process` itself, as failure to start might be acceptable if the client is already partially removed, but logs a warning.

## Service Management:
- **Service List**: Services are defined in an array (`$SccmServices`) for easier management.
- **Service Stop with Timeout**: The script now actively waits for services to stop using a `while` loop and a timeout, providing more reliable service termination before attempting deletion.
- **Service Deletion**: Uses `sc.exe delete $ServiceName` for deleting services. This is a more direct way to remove service entries. It also checks `$LASTEXITCODE` from `sc.exe`.
- **Process Termination**: Added a specific step to ensure the `CcmExec` process is terminated, using `Stop-Process -Force` if necessary, after attempting to stop the service.

## WMI Namespace Removal:
- **Modern Cmdlet**: Switched from `Get-WmiObject` and `Remove-WmiObject` to the more modern `Get-CimInstance` and `Remove-CimInstance`.
- **Error Handling**: Encapsulated in a `try/catch` block to handle potential errors during WMI operations more gracefully and log them.
- **Existence Check**: `Get-CimInstance` is used to check if the namespace exists before attempting removal.

## Registry and File System Operations:
- **Path Arrays**: Paths for registry keys and file system items are stored in arrays for easier iteration.
- **Test-Path Before Removal**: The script now checks if a registry key or file/folder exists using `Test-Path` before attempting to remove it. This avoids unnecessary errors and allows for specific logging if an item is already gone.
- **ShouldProcess Integration**: All removal operations (`Remove-Item`, `sc.exe delete`, `Remove-CimInstance`) are wrapped in `if ($PSCmdlet.ShouldProcess(...))` blocks. This means if you run the script with `-WhatIf`, it will show you what it would do without actually doing it. If you run with `-Confirm`, it will ask for confirmation before each destructive action.
- **Wildcard File Removal**: The duplicate `SMS*.mif` removal was consolidated. `Get-ChildItem` is used to find files matching the pattern before piping to `Remove-Item`.
- **Feedback on Removal**: Added checks after `Remove-Item` to log whether the removal was successful or if the item still exists.

## Error Handling and Logging:
- **Specific try/catch Blocks**: More specific `try/catch` blocks are used around operations that might fail (e.g., WMI, service deletion).
- **Informative Logging**: The `Write-Log` function provides consistent and informative output, including warnings for non-critical issues (e.g., item not found) and errors for critical failures.
- **Main try/catch Block**: The entire `process` block is wrapped in a `try/catch` to capture any unexpected script-terminating errors.

## Clarity and Readability:
- **Variable Names**: Maintained clear variable names.
- **Code Formatting**: Improved code formatting for better readability.

This revised script is more robust, provides better feedback during execution, and incorporates safety features like `-WhatIf` support. Remember to always test such scripts in a non-production environment first.
