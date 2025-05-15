<#
.SYNOPSIS
    Forcefully removes the SCCM (Configuration Manager) client from a Windows system.
    This script attempts a graceful uninstall first, then proceeds to remove services,
    WMI objects, registry keys, and file system artifacts.

.DESCRIPTION
    The script performs the following actions:
    1. Attempts to run the official SCCM client uninstaller.
    2. Stops and removes SCCM-related services.
    3. Removes SCCM WMI namespaces.
    4. Deletes SCCM-related registry keys.
    5. Removes SCCM client folders and files from the Windows directory.
    6. Resets MDM Authority registry key.

    It includes verbose logging and improved error handling.

.NOTES
    Run this script with administrative privileges.
    Use with caution, as this script performs significant system modifications.
    It is recommended to back up critical data before running this script.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

begin {
    Write-Verbose "Starting SCCM Client Removal Script."
    Write-Verbose "Running with user: $(whoami)"

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script must be run with Administrator privileges. Please re-run as Administrator."
        exit 1
    }

    # Function to log messages
    function Write-Log {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Message,
            [ValidateSet("INFO", "WARN", "ERROR")]
            [string]$Level = "INFO"
        )
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogEntry = "$Timestamp [$Level] $Message"
        Write-Host $LogEntry
        # Optionally, output to a log file as well
        # Add-Content -Path "C:\SCCM_Removal.log" -Value $LogEntry
    }
}

process {
    try {
        # --- Attempt Graceful Uninstall ---
        Write-Log "Attempting graceful uninstall of SCCM client..."
        $CcmSetupPath = Join-Path -Path $env:SystemRoot -ChildPath "ccmsetup\ccmsetup.exe" # More robust path construction

        if (Test-Path $CcmSetupPath) {
            if ($PSCmdlet.ShouldProcess($CcmSetupPath, "Execute SCCM Uninstaller")) {
                Write-Log "Found SCCM uninstaller at $CcmSetupPath. Starting uninstall process..."
                $Process = Start-Process -FilePath $CcmSetupPath -ArgumentList "/uninstall" -Wait -PassThru -ErrorAction SilentlyContinue -NoNewWindow
                if ($Process) {
                    Write-Log "SCCM uninstaller process completed with exit code: $($Process.ExitCode)."
                } else {
                    Write-Log "Failed to start SCCM uninstaller process or it was not found. This might be okay if client is already partially removed." -Level WARN
                }
            }
        } else {
            Write-Log "SCCM uninstaller ($CcmSetupPath) not found. Proceeding with manual removal steps." -Level WARN
        }

        # --- Stop and Remove Services ---
        Write-Log "Stopping and removing SCCM services..."
        $SccmServices = @(
            "ccmsetup",
            "CcmExec",
            "smstsmgr",
            "CmRcService"
            # Add any other relevant services here
        )

        foreach ($ServiceName in $SccmServices) {
            Write-Log "Processing service: $ServiceName"
            $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

            if ($Service) {
                if ($Service.Status -ne "Stopped") {
                    if ($PSCmdlet.ShouldProcess($ServiceName, "Stop Service")) {
                        Write-Log "Stopping service: $ServiceName..."
                        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
                        # Wait for the service to actually stop
                        $Timeout = New-TimeSpan -Seconds 30
                        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
                        while ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue).Status -ne "Stopped" -and $StopWatch.Elapsed -lt $Timeout) {
                            Start-Sleep -Seconds 1
                        }
                        if ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue).Status -ne "Stopped") {
                             Write-Log "Service $ServiceName did not stop within the timeout period." -Level WARN
                        } else {
                             Write-Log "Service $ServiceName stopped successfully."
                        }
                    }
                } else {
                    Write-Log "Service $ServiceName is already stopped."
                }

                # Attempt to remove the service using sc.exe as Remove-Service is not available on older PS versions
                # and Set-Service -StartupType Disabled is less aggressive.
                if ($PSCmdlet.ShouldProcess($ServiceName, "Delete Service (using sc.exe)")) {
                    Write-Log "Attempting to delete service: $ServiceName using sc.exe."
                    $deleteResult = sc.exe delete $ServiceName 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Service $ServiceName deleted successfully or was already removed."
                    } else {
                        Write-Log "Failed to delete service $ServiceName. SC.exe output: $deleteResult" -Level WARN
                    }
                }
            } else {
                Write-Log "Service $ServiceName not found." -Level WARN
            }
        }
        
        # Additional wait/check for ccmexec process termination after service stop attempts
        Write-Log "Ensuring CcmExec process is terminated..."
        $CcmExecProcess = Get-Process -Name "CcmExec" -ErrorAction SilentlyContinue
        if ($CcmExecProcess) {
            Write-Log "CcmExec process found. Attempting to wait for graceful exit..."
            try {
                $CcmExecProcess | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Log "CcmExec process forcefully stopped."
            } catch {
                Write-Log "Error stopping CcmExec process: $($_.Exception.Message)" -Level ERROR
            }
        } else {
            Write-Log "CcmExec process not running."
        }


        # --- Remove WMI Namespaces ---
        Write-Log "Removing WMI namespaces..."
        $WmiNamespacesToRemove = @(
            @{ Path = "root"; Name = "ccm" },
            @{ Path = "root\cimv2"; Name = "sms" }
            # Add other namespaces if necessary
        )

        foreach ($nsInfo in $WmiNamespacesToRemove) {
            if ($PSCmdlet.ShouldProcess("WMI Namespace $($nsInfo.Path)\$($nsInfo.Name)", "Remove WMI Namespace")) {
                Write-Log "Attempting to remove WMI namespace: $($nsInfo.Path)\$($nsInfo.Name)"
                try {
                    $Namespace = Get-CimInstance -Namespace $nsInfo.Path -Query "SELECT * FROM __Namespace WHERE Name='$($nsInfo.Name)'" -ErrorAction SilentlyContinue
                    if ($Namespace) {
                        Remove-CimInstance -InputObject $Namespace -ErrorAction Stop
                        Write-Log "Successfully removed WMI namespace: $($nsInfo.Path)\$($nsInfo.Name)."
                    } else {
                        Write-Log "WMI namespace '$($nsInfo.Name)' not found in '$($nsInfo.Path)'." -Level WARN
                    }
                } catch {
                    Write-Log "Error removing WMI namespace $($nsInfo.Path)\$($nsInfo.Name): $($_.Exception.Message)" -Level ERROR
                }
            }
        }

        # --- Remove Services from Registry (Redundant if sc.exe delete works, but good for cleanup) ---
        Write-Log "Removing SCCM service entries from registry..."
        $ServiceRegistryPaths = @(
            "HKLM:\SYSTEM\CurrentControlSet\Services\CCMSetup",
            "HKLM:\SYSTEM\CurrentControlSet\Services\CcmExec",
            "HKLM:\SYSTEM\CurrentControlSet\Services\smstsmgr",
            "HKLM:\SYSTEM\CurrentControlSet\Services\CmRcService"
        )
        foreach ($regPath in $ServiceRegistryPaths) {
            if (Test-Path $regPath) {
                if ($PSCmdlet.ShouldProcess($regPath, "Remove Registry Key")) {
                    Write-Log "Removing registry key: $regPath"
                    Remove-Item -Path $regPath -Force -Recurse -ErrorAction SilentlyContinue
                    if (Test-Path $regPath) {
                        Write-Log "Failed to remove registry key: $regPath" -Level WARN
                    } else {
                        Write-Log "Successfully removed registry key: $regPath"
                    }
                }
            } else {
                Write-Log "Registry key $regPath not found." -Level WARN
            }
        }

        # --- Remove SCCM Client Software Registry Keys ---
        Write-Log "Removing SCCM software registry keys..."
        $SoftwareRegistryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\CCM",
            "HKLM:\SOFTWARE\Microsoft\CCMSetup",
            "HKLM:\SOFTWARE\Microsoft\SMS"
        )
        foreach ($regPath in $SoftwareRegistryPaths) {
            if (Test-Path $regPath) {
                if ($PSCmdlet.ShouldProcess($regPath, "Remove Registry Key")) {
                    Write-Log "Removing registry key: $regPath"
                    Remove-Item -Path $regPath -Force -Recurse -ErrorAction SilentlyContinue
                     if (Test-Path $regPath) {
                        Write-Log "Failed to remove registry key: $regPath" -Level WARN
                    } else {
                        Write-Log "Successfully removed registry key: $regPath"
                    }
                }
            } else {
                Write-Log "Registry key $regPath not found." -Level WARN
            }
        }

        # --- Reset MDM Authority ---
        Write-Log "Resetting MDM Authority registry key..."
        $MdmRegPath = "HKLM:\SOFTWARE\Microsoft\DeviceManageabilityCSP"
        if (Test-Path $MdmRegPath) {
            if ($PSCmdlet.ShouldProcess($MdmRegPath, "Remove Registry Key")) {
                Write-Log "Removing MDM registry key: $MdmRegPath"
                Remove-Item -Path $MdmRegPath -Force -Recurse -ErrorAction SilentlyContinue
                if (Test-Path $MdmRegPath) {
                    Write-Log "Failed to remove MDM registry key: $MdmRegPath" -Level WARN
                } else {
                    Write-Log "Successfully removed MDM registry key: $MdmRegPath"
                }
            }
        } else {
            Write-Log "MDM registry key $MdmRegPath not found." -Level WARN
        }

        # --- Remove Folders and Files ---
        Write-Log "Removing SCCM folders and files..."
        $WinDir = $env:WinDir
        $PathsToRemove = @(
            Join-Path -Path $WinDir -ChildPath "CCM",
            Join-Path -Path $WinDir -ChildPath "ccmsetup",
            Join-Path -Path $WinDir -ChildPath "ccmcache",
            Join-Path -Path $WinDir -ChildPath "SMSCFG.ini"
        )

        # Add wildcard file removals separately
        $WildcardFiles = @(
            Join-Path -Path $WinDir -ChildPath "SMS*.mif" # Handles both SMS*.mif entries from original
        )

        foreach ($itemPath in $PathsToRemove) {
            if (Test-Path $itemPath) {
                if ($PSCmdlet.ShouldProcess($itemPath, "Remove File/Folder")) {
                    Write-Log "Removing path: $itemPath"
                    Remove-Item -Path $itemPath -Force -Recurse -ErrorAction SilentlyContinue
                    if (Test-Path $itemPath) {
                        Write-Log "Failed to remove path: $itemPath" -Level WARN
                    } else {
                        Write-Log "Successfully removed path: $itemPath"
                    }
                }
            } else {
                Write-Log "Path $itemPath not found." -Level WARN
            }
        }
        
        foreach ($itemPattern in $WildcardFiles) {
             if ($PSCmdlet.ShouldProcess($itemPattern, "Remove Files by Pattern")) {
                Write-Log "Removing files matching pattern: $itemPattern"
                Get-ChildItem -Path $itemPattern -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                # Verification for wildcard removal is trickier, so we'll assume success if no errors are thrown by Remove-Item
                Write-Log "Attempted removal of files matching: $itemPattern. Check logs for errors if any."
             }
        }

        Write-Log "SCCM Client removal process completed." -Level INFO
        Write-Log "A reboot may be required to finalize all changes." -Level WARN

    } catch {
        Write-Log "An unexpected error occurred during SCCM removal: $($_.Exception.Message)" -Level ERROR
        Write-Log "Script execution halted." -Level ERROR
        # You might want to exit with a non-zero code here
        # exit 1 
    }
}

end {
    Write-Verbose "SCCM Client Removal Script finished."
}
