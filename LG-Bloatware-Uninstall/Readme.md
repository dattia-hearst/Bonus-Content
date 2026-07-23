# LG Monitor App Removal Scripts

These three PowerShell scripts detect and remove the **LG Monitor App** (`LGElectronics.LGMonitorApp`) — the bloatware that LG silently installson systems connected to LG monitors — and apply a registry policy to prevent it from being reinstalled.

---

## Scripts

### `LG_Scanner.ps1` — Detection

Checks whether the LG Monitor App is currently installed on the machine.

Queries `Get-AppxPackage` across all user profiles and returns a simple object:

| Field | Description |
|---|---|
| `Name` | The package name being checked |
| `Installed` | `True` if the package is found, `False` if not |
| `Version` | Version string if installed, blank if not |

Run this first to confirm whether the bloatware is present before taking action.

**PDQ Connect / PDQ Deploy:** Use `LG_Scanner.ps1` as a scan script to report which machines in your environment have the LG Monitor App installed. In Connect, add it as a PowerShell step in a scan profile; in Deploy, use it as a scan step in a package to target only affected machines.

---

### `LG_Reg.ps1` — Registry Policy

Creates or updates a registry key that blocks Windows from pulling device metadata (including the LG Monitor App) from the network.

**Registry path:** `HKLM:\Software\Policies\Microsoft\Windows\Device Metadata`  
**Value set:** `PreventDeviceMetadataFromNetwork = 1 (DWORD)`

If the key doesn't exist, the script creates it. If it does, the value is overwritten. Either way, the script confirms what it did with console output.

Run this to prevent the bloatware from reinstalling itself after removal.

**PDQ Connect / PDQ Deploy:** Add `LG_Reg.ps1` as a PowerShell step in a package to deploy the registry policy across your fleet.

---

### `LG_Uninstall.ps1` — Removal

Uninstalls the LG Monitor App for all users and removes it from the provisioned package list so it won't be re-deployed to new user profiles on the same machine.

**PDQ Connect / PDQ Deploy:** Add `LG_Uninstall.ps1` as a PowerShell step in a package to remove the app at scale. Pair it with `LG_Scanner.ps1` as a scan condition so the package only runs on machines where the app is detected.

Runs two operations:
1. `Remove-AppxPackage -AllUsers` — removes the installed package from all existing user accounts
2. `Remove-AppxProvisionedPackage -Online` — removes the provisioned (staged) package so it won't be auto-installed for future users

---

## Recommended Order of Operations

1. **`LG_Scanner.ps1`** — confirm the app is present
2. **`LG_Uninstall.ps1`** — remove it
3. **`LG_Reg.ps1`** — lock the door so it doesn't come back
4. **`LG_Scanner.ps1`** again — verify `Installed` returns `False`

---
