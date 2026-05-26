<#
.SYNOPSIS
    Returns an inventory of all attached monitors, including internal laptop panels.

.DESCRIPTION
    PowerShell Scanner for PDQ Connect / PDQ Inventory that returns one row per
    monitor with manufacturer, model, serial number, manufacture date, physical
    size, native resolution, and connection type.

    Works on desktops and laptops. Undocked laptops will only return the
    internal panel. Virtual / RDP sessions may return limited data.
#>

# --- VM detection ---
# If this is a VM, EDID data is either missing or synthetic, so return a
# single informational row instead of trying to enumerate virtual displays.
$cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$vmPattern = 'Virtual Machine|VMware|VirtualBox|KVM|QEMU|Xen|Parallels|Hyper-V|Bochs|Google Compute Engine'
$isVM = ($cs.Model -match $vmPattern) -or ($cs.Manufacturer -match $vmPattern)

if ($isVM) {
    [PSCustomObject]@{
        Manufacturer       = 'N/A'
        ManufacturerCode   = $null
        Model              = $null
        SerialNumber       = $null
        YearOfManufacture  = $null
        WeekOfManufacture  = $null
        DiagonalSizeInches = $null
        NativeResolution   = $null
        ConnectionType     = $null
        IsInternalPanel    = $false
        Active             = $false
        IsVirtualMachine   = $true
        Note               = "Virtual machine detected ($($cs.Manufacturer) / $($cs.Model)) - no physical monitor data available"
    }
    return
}

# Lookup table of common monitor PNP manufacturer IDs.
# Unknown codes fall back to the raw 3-letter code.
$pnpIds = @{
    'AUO' = 'AU Optronics';       'BOE' = 'BOE Technology';   'CMN' = 'Chimei Innolux'
    'LGD' = 'LG Display';         'SHP' = 'Sharp';            'SEC' = 'Samsung';
    'SAM' = 'Samsung';            'DEL' = 'Dell';             'HWP' = 'HP';
    'LEN' = 'Lenovo';             'ACR' = 'Acer';             'AOC' = 'AOC';
    'ACI' = 'Asus';               'AUS' = 'Asus';             'GSM' = 'LG Electronics';
    'BNQ' = 'BenQ';               'PHL' = 'Philips';          'MSI' = 'MSI';
    'VSC' = 'ViewSonic';          'GBT' = 'Gigabyte';         'IVM' = 'Iiyama';
    'EIZ' = 'EIZO';               'NEC' = 'NEC';              'HPN' = 'HP';
    'APP' = 'Apple';              'MEI' = 'Panasonic';        'ENC' = 'Eizo Nanao';
    'ALP' = 'Alienware';          'RTK' = 'Realtek';          'HSD' = 'HannStar';
}

# Pull the main monitor tables once
$ids       = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
$params    = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue
$modes     = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction SilentlyContinue
$conn      = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue

# Video output technology codes from WmiMonitorConnectionParams
$connectionTypes = @{
    -2 = 'Uninitialized'; -1 = 'Other';          0  = 'VGA';
    1  = 'S-Video';        2 = 'Composite';      3  = 'Component';
    4  = 'DVI';            5 = 'HDMI';           6  = 'LVDS';
    8  = 'D-Jpn';          9 = 'SDI';            10 = 'DisplayPort (external)';
    11 = 'DisplayPort (embedded)'; 12 = 'UDI (external)';  13 = 'UDI (embedded)';
    14 = 'SDTV dongle';   15 = 'Miracast';      16 = 'Indirect Wired';
    2147483648 = 'Internal'
}

foreach ($mon in $ids) {

    # Decode byte arrays (null-terminated UInt16 arrays) into readable strings
    $mfgCode = if ($mon.ManufacturerName) {
        ($mon.ManufacturerName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join ''
    } else { $null }

    $model = if ($mon.UserFriendlyName) {
        ($mon.UserFriendlyName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join ''
    } else { $null }

    $serial = if ($mon.SerialNumberID) {
        ($mon.SerialNumberID | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join ''
    } else { $null }

    $manufacturer = if ($mfgCode -and $pnpIds.ContainsKey($mfgCode)) { $pnpIds[$mfgCode] } else { $mfgCode }

    # Match physical size by InstanceName
    $sizeEntry = $params | Where-Object { $_.InstanceName -eq $mon.InstanceName }
    $diagonalInches = $null
    if ($sizeEntry -and $sizeEntry.MaxHorizontalImageSize -gt 0 -and $sizeEntry.MaxVerticalImageSize -gt 0) {
        $h = $sizeEntry.MaxHorizontalImageSize   # centimeters
        $v = $sizeEntry.MaxVerticalImageSize
        $diagonalCm = [math]::Sqrt(($h * $h) + ($v * $v))
        $diagonalInches = [math]::Round($diagonalCm / 2.54, 1)
    }

    # Native resolution = highest supported mode
    $modeEntry = $modes | Where-Object { $_.InstanceName -eq $mon.InstanceName }
    $nativeResolution = $null
    if ($modeEntry -and $modeEntry.MonitorSourceModes) {
        $best = $modeEntry.MonitorSourceModes |
            Sort-Object -Property HorizontalActivePixels -Descending |
            Select-Object -First 1
        if ($best) {
            $nativeResolution = "$($best.HorizontalActivePixels)x$($best.VerticalActivePixels)"
        }
    }

    # Connection type
    $connEntry = $conn | Where-Object { $_.InstanceName -eq $mon.InstanceName }
    $connectionType = $null
    if ($connEntry) {
        $code = [int64]$connEntry.VideoOutputTechnology
        $connectionType = if ($connectionTypes.ContainsKey($code)) { $connectionTypes[$code] } else { "Unknown ($code)" }
    }

    $isInternal = ($connectionType -match 'Internal|embedded|LVDS')

    [PSCustomObject]@{
        Manufacturer       = $manufacturer
        ManufacturerCode   = $mfgCode
        Model              = $model
        SerialNumber       = $serial
        YearOfManufacture  = $mon.YearOfManufacture
        WeekOfManufacture  = $mon.WeekOfManufacture
        DiagonalSizeInches = $diagonalInches
        NativeResolution   = $nativeResolution
        ConnectionType     = $connectionType
        IsInternalPanel    = [bool]$isInternal
        Active             = [bool]$mon.Active
        IsVirtualMachine   = $false
        Note               = $null
    }
}