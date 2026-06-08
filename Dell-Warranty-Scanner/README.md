# Dell Warranty Scanner

A PDQ Connect script that retrieves Dell warranty information from any managed Dell device.

## What It Does

1. Grabs the device's Dell service tag via WMI
2. Runs the Dell Command | Warranty CLI to pull warranty data from Dell's servers
3. Caches the result locally for 30 days — no redundant lookups on repeat runs
4. Returns warranty start/end dates alongside a scan status

## Requirements

**Dell Command | Warranty CLI** must be installed on each target device before running this script.

- Download & docs: https://www.dell.com/support/kbdoc/en-us/000146749/dell-command-warranty
- Silent install: `DellWarranty-CLI.exe /Q /v/qn`

## Output

| Field | Description |
|---|---|
| Service Tag | Dell service tag pulled from the device |
| Warranty Start Date | Earliest-to-latest warranty start (yyyy-MM-dd) |
| Warranty End Date | Latest warranty end date (yyyy-MM-dd) |
| Status | Fresh Scan / Cached / CLI Not Installed / No Data Found |

## Usage

Deploy via PDQ Connect as a PowerShell script. Results surface directly in the Connect report view.

## Shown In

PDQ Webcast — 5/28
