<#
.SYNOPSIS
    Returns an inventory of all graphics adapters (GPUs) in the machine.

.DESCRIPTION
    PowerShell Scanner for PDQ Connect / PDQ Inventory that returns one row per
    video adapter, including integrated and discrete GPUs. Useful for planning
    driver rollouts, identifying machines needing GPU upgrades, tracking VRAM
    for workloads like CAD / AI / video editing, and finding outdated drivers.

    Data comes from Win32_VideoController. VRAM reported via AdapterRAM is
    capped at 4 GB by WMI on older systems; we fall back to the registry for
    discrete cards reporting 4096 MB exactly, which is often truncation.
#>

$cards = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue

foreach ($card in $cards) {

    # AdapterRAM is a UInt32 and caps at ~4 GB. Try the registry for a true value.
    $vramMB = $null
    if ($card.AdapterRAM) {
        $vramMB = [math]::Round($card.AdapterRAM / 1MB, 0)
    }

    # Registry fallback for cards that likely have more than 4 GB
    if ($vramMB -in @(4095, 4096)) {
        try {
            $gpuKeys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction Stop |
                Where-Object { $_.PSChildName -match '^\d{4}$' }

            foreach ($key in $gpuKeys) {
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if ($props.'HardwareInformation.qwMemorySize') {
                    $regVram = [math]::Round($props.'HardwareInformation.qwMemorySize' / 1MB, 0)
                    if ($props.'DriverDesc' -eq $card.Name -and $regVram -gt $vramMB) {
                        $vramMB = $regVram
                        break
                    }
                }
            }
        } catch {}
    }

    # Driver date comes back as a CIM datetime; pull just the date portion
    $driverDate = $null
    if ($card.DriverDate) {
        $driverDate = $card.DriverDate.ToString('yyyy-MM-dd')
    }

    # Figure out if this is likely integrated based on name patterns
    $isIntegrated = $card.Name -match 'Intel.*(HD|UHD|Iris|Graphics)|AMD Radeon\(TM\) Graphics|Microsoft Basic Display|Microsoft Remote Display|Parsec'

    # Flag drivers older than a year
    $driverAgeDays = $null
    if ($card.DriverDate) {
        $driverAgeDays = [math]::Round(((Get-Date) - $card.DriverDate).TotalDays, 0)
    }

    [PSCustomObject]@{
        Name              = $card.Name
        Manufacturer      = $card.AdapterCompatibility
        VideoProcessor    = $card.VideoProcessor
        VRAM_MB           = $vramMB
        CurrentResolution = if ($card.CurrentHorizontalResolution) { "$($card.CurrentHorizontalResolution)x$($card.CurrentVerticalResolution) @ $($card.CurrentRefreshRate)Hz" } else { $null }
        DriverVersion     = $card.DriverVersion
        DriverDate        = $driverDate
        DriverAgeDays     = $driverAgeDays
        VideoMode         = $card.VideoModeDescription
        Status            = $card.Status
        IsIntegrated      = [bool]$isIntegrated
    }
}