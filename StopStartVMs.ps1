<#
.SYNOPSIS
    Azure Automation runbook for managing VM power states based on schedules.

.DESCRIPTION
    This script evaluates Azure virtual machines to determine whether they should be powered on or off based on two tags:
    - `AutoShutdownSchedule`: Defines the times/days when the VM should be powered on.
    - `NoStartSchedule`: Defines the times/days when the VM should NOT be powered on (takes precedence over `AutoShutdownSchedule`).

.NOTES
    Author         : J. Andres Bergano G.  - @andresb39
    Version        : 2.0
    Date           : 2025-01-21
    Credits        : Based on https://github.com/tomasrudh/AutoShutdownSchedule

.PARAMETERS
    No specific parameters required. The script operates based on tags defined on the VMs.

#>

# Function to evaluate whether the current time falls within a specified range or matches a specific day
# Parameters:
# - TimeRange: The time range or day to check (e.g., "8->19", "Sunday")
# - AllowStart: Boolean indicating whether the VM is allowed to start
function CheckScheduleEntry {
    param (
        [string]$TimeRange,
        [bool]$AllowStart
    )

    $rangeStart, $rangeEnd = $null
    $currentTime = (Get-Date).ToLocalTime()
    $midnight = $currentTime.AddDays(1).Date

    try {
        # Handle time ranges (e.g., "8->19")
        if ($TimeRange -like "*->*") {
            $timeRangeComponents = $TimeRange -split "->" | ForEach-Object { $_.Trim() }
            $rangeStart = Get-Date $timeRangeComponents[0]
            $rangeEnd = Get-Date $timeRangeComponents[1]

            # Adjust for ranges crossing midnight
            if ($rangeStart -gt $rangeEnd) {
                if ($currentTime -ge $rangeStart -and $currentTime -lt $midnight) {
                    $rangeEnd = $rangeEnd.AddDays(1)
                } else {
                    $rangeStart = $rangeStart.AddDays(-1)
                }
            }
        }
        # Handle specific days (e.g., "Sunday") or specific dates (e.g., "December 25")
        else {
            if ([System.DayOfWeek].GetEnumValues() -contains $TimeRange) {
                if ($TimeRange -eq (Get-Date).DayOfWeek.ToString()) {
                    $rangeStart = Get-Date "00:00"
                    $rangeEnd = $rangeStart.AddHours(23).AddMinutes(59).AddSeconds(59)
                }
            } elseif (Get-Date $TimeRange) {
                $parsedDay = Get-Date $TimeRange
                $rangeStart = $parsedDay
                $rangeEnd = $parsedDay.AddHours(23).AddMinutes(59).AddSeconds(59)
            }
        }
    } catch {
        Write-Output "WARNING: Invalid time range [$TimeRange]. Details: $($_.Exception.Message)"
        return $false
    }

    # Return true if the current time does not match a no-start range
    if ($AllowStart -eq $false -and $currentTime -ge $rangeStart -and $currentTime -le $rangeEnd) {
        return $false
    }
    return $true
}

# Function to process a VM and determine its desired state
# Parameters:
# - VM: The VM object to process
# - VMList: A list of all VMs in the subscription
function ProcessVM {
    param (
        [object]$VM,
        [object[]]$VMList
    )

    # Retrieve tags for schedules
    $autoStartSchedule = $VM.Tags["AutoShutdownSchedule"]
    $noStartSchedule = $VM.Tags["NoStartSchedule"]
    $allowStart = $true

    # Evaluate `NoStartSchedule` to disallow starting in specific ranges
    if ($noStartSchedule) {
        $noStartEntries = $noStartSchedule -split "," | ForEach-Object { $_.Trim() }
        foreach ($entry in $noStartEntries) {
            if (-not (CheckScheduleEntry -TimeRange $entry -AllowStart $false)) {
                Write-Output "[$($VM.Name)]: Starting is not allowed during the range [$entry]."
                $allowStart = $false
                break
            }
        }
    }

    # Evaluate `AutoShutdownSchedule` only if starting is allowed
    if ($allowStart -and $autoStartSchedule) {
        $startEntries = $autoStartSchedule -split "," | ForEach-Object { $_.Trim() }
        $shouldStart = $false

        foreach ($entry in $startEntries) {
            if (CheckScheduleEntry -TimeRange $entry -AllowStart $true) {
                $shouldStart = $true
                break
            }
        }

        # Determine the desired state based on the schedule
        $desiredState = $shouldStart ? "Started" : "StoppedDeallocated"
        Write-Output "[$($VM.Name)]: Desired state: [$desiredState]."
        EnsureVMState -VM $VM -VMList $VMList -DesiredState $desiredState
    } elseif (-not $allowStart) {
        # If `NoStartSchedule` disallows starting, ensure the VM is deallocated
        Write-Output "[$($VM.Name)]: NoStartSchedule active. Desired state: [StoppedDeallocated]."
        EnsureVMState -VM $VM -VMList $VMList -DesiredState "StoppedDeallocated"
    }
}

# Function to ensure the VM matches its desired state
# Parameters:
# - VM: The VM object
# - VMList: A list of all VMs in the subscription
# - DesiredState: The state to enforce ("Started" or "StoppedDeallocated")
function EnsureVMState {
    param (
        [object]$VM,
        [object[]]$VMList,
        [string]$DesiredState
    )

    # Retrieve the current status of the VM
    $vmStatus = Get-AzVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status
    $currentState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState*" }).Code -replace "PowerState/", ""

    # Start or stop the VM based on the desired state
    if ($DesiredState -eq "Started" -and $currentState -ne "running") {
        Write-Output "[$($VM.Name)]: Starting VM..."
        Start-AzVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -NoWait | Out-Null
        Start-Sleep -Seconds 20 # Optional: Adjust the wait time as necessary
        $vmStatus = Get-AzVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status
        $currentState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState*" }).Code -replace "PowerState/", ""
        if ($currentState -eq "running") {
            Write-Output "[$($VM.Name)]: The VM is now running."
        } else {
            Write-Output "[$($VM.Name)]: Failed to start the VM."
        }
    } elseif ($DesiredState -eq "StoppedDeallocated" -and $currentState -ne "deallocated") {
        Write-Output "[$($VM.Name)]: Stopping VM..."
        Stop-AzVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -NoWait -Force | Out-Null
        Start-Sleep -Seconds 20 # Optional: Adjust the wait time as necessary
        $vmStatus = Get-AzVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status
        $currentState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState*" }).Code -replace "PowerState/", ""
        if ($currentState -eq "deallocated") {
            Write-Output "[$($VM.Name)]: The VM is now stopped and deallocated."
        } else {
            Write-Output "[$($VM.Name)]: Failed to stop the VM."
        }
    } else {
        Write-Output "[$($VM.Name)]: The current state [$currentState] matches the desired state [$DesiredState]. No action needed."
    }
}


# Main logic: Connect to Azure and process all VMs
try {
    # Disable context autosave and authenticate with Azure
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity | Out-Null

    # Retrieve all VMs in the subscription
    $resourceManagerVMList = Get-AzVM | Sort-Object Name

    # Process each VM
    foreach ($vm in $resourceManagerVMList) {
        ProcessVM -VM $vm -VMList $resourceManagerVMList
    }
} catch {
    # Handle any errors during execution
    Write-Output "ERROR: $($_.Exception.Message)"
}

