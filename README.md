# AutoShutdownSchedule for Azure Virtual Machines

## Overview

This project provides an Azure Automation Runbook for managing the power states of Azure Virtual Machines (VMs) based on tags. It allows you to schedule when VMs should be turned on or off using two customizable tags:

- **`AutoShutdownSchedule`**: Specifies when a VM should be powered **on**.
- **`NoStartSchedule`**: Specifies when a VM should **not** be powered on (takes precedence over `AutoShutdownSchedule`).

The script ensures cost savings by automating VM power management and enforces business logic to align with operational requirements.

---

## Features

- **Flexible Scheduling**:
  - Use `AutoShutdownSchedule` to define the days and times VMs should be turned **on**.
  - Use `NoStartSchedule` to block specific days or time ranges when VMs must remain **off**.
- **Priority Handling**:
  - The `NoStartSchedule` tag takes precedence over `AutoShutdownSchedule`.
- **Supports Complex Scenarios**:
  - Handles time ranges crossing midnight.
  - Supports both daily and specific date schedules.
- **Logging**:
  - Provides detailed logs for actions taken, including skipped or invalid configurations.

---

## How It Works

### Tags

The script evaluates two tags on each VM:

1. **`AutoShutdownSchedule`**:

   - Defines when the VM should be turned on.
   - Example: `8->19,Monday,Wednesday` (turn on from 8:00 AM to 7:00 PM on Monday and Wednesday).

2. **`NoStartSchedule`**:
   - Defines when the VM should not be turned on.
   - Example: `Sunday,19:00->08:00` (do not turn on the VM on Sundays or between 7:00 PM and 8:00 AM).

The script enforces the following logic:

1. If `NoStartSchedule` matches the current time, the VM will remain off.
2. If `AutoShutdownSchedule` matches and `NoStartSchedule` does not, the VM will turn on.

---

## Requirements

- **Azure Environment**:
  - Azure Subscription
  - Azure Automation Account
- **PowerShell Modules**:
  - `Az.Accounts`
  - `Az.Compute`
  - `Az.Resources`
- **Managed Identity**:
  - The script uses a system-assigned or user-assigned managed identity for authentication.
- **VM Tags**:
  - Add the tags `AutoShutdownSchedule` and/or `NoStartSchedule` to your VMs.

---

## Setup

### Step 1: Deploy the Script

1. Create an Azure Automation account if you don't have one.
2. Import the required PowerShell modules (`Az.Accounts`, `Az.Compute`, `Az.Resources`) into the Automation account.
3. Add the script as a new runbook in the Automation account.

### Step 2: Assign Managed Identity

1. Enable a system-assigned or user-assigned managed identity for the Automation account.
2. Grant the managed identity the following permissions:
   - `Virtual Machine Contributor` (to start and stop VMs).
   - `Reader` (to read VM tags).

### Step 3: Add Tags to VMs

1. Navigate to your Azure VMs in the Azure Portal.
2. Add the following tags:
   - **Key**: `AutoShutdownSchedule`
   - **Value**: (e.g., `8->19,Monday,Wednesday`)
   - **Key**: `NoStartSchedule`
   - **Value**: (e.g., `Sunday,19:00->08:00`)

---

## Usage

### Run the Script

1. Open the Azure Automation account.
2. Select the runbook and click **Start**.
3. Optionally, enable the runbook to run on a schedule (e.g., every hour).

### Logs

The script outputs logs to track:

- Current time and tag evaluations.
- Actions taken (start/stop VMs).
- Warnings for invalid configurations.

---

## Examples

### Example Tags

1. **`AutoShutdownSchedule`**:

   ```plaintext
   8->19,Monday,Wednesday
   ```

   - Turn on the VM on Monday and Wednesday between 8:00 AM and 7:00 PM.

2. **`NoStartSchedule`**:

   ```plaintext
   Sunday,19:00->08:00
   ```

   - Do not start the VM on Sundays or between 7:00 PM and 8:00 AM.

3. **Combined**:
   - The `NoStartSchedule` tag will override the `AutoShutdownSchedule` tag if there is a conflict.

---

## Script Structure

### Functions

1. **`CheckScheduleEntry`**:
   - Evaluates if the current time matches a given time range or day.
   - Handles ranges crossing midnight and specific days.
2. **`ProcessVM`**:
   - Determines the desired state of a VM based on the tags.
   - Enforces `NoStartSchedule` logic first, followed by `AutoShutdownSchedule`.
3. **`EnsureVMState`**:
   - Ensures the VM's power state matches the desired state (`Started` or `StoppedDeallocated`).

---

## Notes

- **Author**: J. Andres Bergano G.
- **Version**: 2.0
- **Date**: 2025-01-21
- **Credits**: Based on [AutoShutdownSchedule](https://github.com/tomasrudh/AutoShutdownSchedule).

---

## License

This script is distributed under the MIT License. See the original project [AutoShutdownSchedule](https://github.com/tomasrudh/AutoShutdownSchedule) for more details.
