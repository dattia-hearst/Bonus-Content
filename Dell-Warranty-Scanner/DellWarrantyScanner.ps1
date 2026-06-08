<#
.SYNOPSIS
    Retrieves Dell warranty information for the local device using Dell Command | Warranty CLI.

.DESCRIPTION
    Queries the device's service tag via WMI, then uses the Dell Command | Warranty CLI tool
    to fetch warranty start and end dates from Dell's servers. Results are cached locally for
    30 days to avoid redundant lookups. Returns a structured object with the service tag,
    warranty dates, and scan status.

.REQUIREMENTS
    - Dell Command | Warranty CLI must be installed on the target device.
    - Download: https://www.dell.com/support/kbdoc/en-us/000146749/dell-command-warranty
    - Silent install switch: /Q /v/qn

.OUTPUTS
    PSCustomObject with:
      - Service Tag
      - Warranty Start Date (yyyy-MM-dd)
      - Warranty End Date   (yyyy-MM-dd)
      - Status: "Fresh Scan", "Cached (Age: X days)", "CLI Tool Not Installed", or "No Warranty Data Found"

.NOTES
    Webcast: PDQ Webcast 5/28
    Cache duration is controlled by $CacheDays (default: 30)
#>
$tempPath = $env:TEMP
$TagFile = Join-Path -Path $tempPath -ChildPath "servicetag.csv"
$WarrantyFile = Join-Path -Path $tempPath -ChildPath "warranty.csv"
$cliPath = "C:\Program Files (x86)\Dell\CommandIntegrationSuite\DellWarranty-CLI.exe" #https://www.dell.com/support/kbdoc/en-us/000146749/dell-command-warranty
#to install silent the exe switch is /Q /v/qn

$CacheDays = 30

# 1. Get Service Tag
$ServiceTag = (Get-CimInstance Win32_BIOS).SerialNumber

# 2. Determine if we need to run a fresh scan
$NeedsUpdate = $true
if (Test-Path $WarrantyFile) {
    $FileAge = (Get-Date) - (Get-Item $WarrantyFile).LastWriteTime
    if ($FileAge.Days -lt $CacheDays) {
        $NeedsUpdate = $false
    }
}

# 3. Run the EXE only if needed
if ($NeedsUpdate) {
    if (Test-Path $cliPath) {
        $ServiceTag | Out-File -FilePath $TagFile -Encoding ascii
        & $cliPath /I="$TagFile" /E="$WarrantyFile" *> $null
        if (Test-Path $TagFile) { Remove-Item $TagFile -Force }
    }
    else {
        return [PSCustomObject]@{
            "Service Tag"         = $ServiceTag
            "Warranty Start Date" = $null
            "Warranty End Date"   = $null
            "Status"              = "CLI Tool Not Installed"
        }
    }
}

# 4. Import and Parse the (New or Cached) file
if ((Test-Path $WarrantyFile) -and (Get-Item $WarrantyFile).Length -gt 0) {
    $rawCSV = Import-Csv -Path $WarrantyFile

    $latestStart = ($rawCSV | ForEach-Object { [datetime]$_."Start Date" } | Sort-Object -Descending | Select-Object -First 1)
    $latestEnd   = ($rawCSV | ForEach-Object { [datetime]$_."End Date" }   | Sort-Object -Descending | Select-Object -First 1)

    $Result = [PSCustomObject]@{
        "Service Tag"         = $ServiceTag
        "Warranty Start Date" = $latestStart.ToString("yyyy-MM-dd")
        "Warranty End Date"   = $latestEnd.ToString("yyyy-MM-dd")
        "Status"              = if ($NeedsUpdate) { "Fresh Scan" } else { "Cached (Age: $($FileAge.Days) days)" }
    }
}
else {
    $Result = [PSCustomObject]@{
        "Service Tag"         = $ServiceTag
        "Warranty Start Date" = $null
        "Warranty End Date"   = $null
        "Status"              = "No Warranty Data Found"
    }
}

$Result