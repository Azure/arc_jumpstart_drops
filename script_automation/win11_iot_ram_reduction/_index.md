---
type: docs
title: "Windows 11 IoT Enterprise RAM Reduction Guide"
linkTitle: "Windows 11 IoT Enterprise RAM Reduction Guide"
weight: 1
description: >
---

## Windows 11 IoT Enterprise RAM Reduction Guide

This repository offers a practical solution for optimizing Windows 11 IoT Enterprise by reducing its RAM usage. It includes a `configure_services_final.bat` batch file that utilizes the Windows `sysprep` package to streamline system services. By disabling non-essential services, commonly referred to as 'bloat', this guide helps achieve a significantly lower RAM footprint, thus enhancing the performance and reliability of IoT devices.

## Contributors

This Jumpstart Drop was originally written by the following contributors:

- [Lakshit Dabas | Product Manager](https://www.linkedin.com/in/lakshitdabas)

## Prerequisites

- **Operating System:** Windows 11 IoT Enterprise 22H2 Image or later.
- **Administrative Access:** System with administrative privileges.
- **Technical Knowledge:** Familiarity with command-line operations and system configuration.

## Getting Started

### Entering Audit Mode

Prepare the system for modifications in audit mode.

1. **Access Command Prompt with Admin Rights:**

- Use the shortcut `Win + X`.
- Select **Windows Terminal (Admin)** or **Command Prompt (Admin)**.
  
2. **Navigate to SysPrep:**

- Type `cd C:\Windows\System32\SysPrep` in the command prompt.
- Press Enter.

1. **Initiate Audit Mode:**

  - Enter the command `sysprep /audit`.
  - The system will restart as part of this process.
  - Upon booting, a dialog box will appear. Ignore this dialog box for now.

### Optimization Script Execution

After restarting in audit mode:

1. **Download the Script:**

- In the Command Prompt, input:

```bash
curl -L https://raw.githubusercontent.com/Azure/arc_jumpstart_drops/main/script_automation/win11_iot_ram_reduction/configure_services_final.bat -o configure_services_final.bat
```

- This downloads a batch script for service optimization.

1. **Run the Script:**

- Execute the script with administrative privileges.
- Reboot your machine post-execution to apply the changes.

## Additional Information

- **RAM Usage Variability:** The system's idle RAM usage is influenced by the total available RAM, due to Windows' optimization mechanisms.
- **Service Configuration:** Services such as `hidserv`, `umRDPService`, `SessionEnv`, and `TermService` remain active for testing but can be disabled if unnecessary.
