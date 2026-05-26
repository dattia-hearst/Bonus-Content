<#
.SYNOPSIS
    Returns the default web browser for each user profile on the machine,
    plus the list of all installed browsers.

.DESCRIPTION
    PowerShell Scanner for PDQ Connect / PDQ Inventory that returns one row per
    user profile showing which browser is set as default for HTTPS, along with
    a machine-wide list of every installed browser it can detect.

    Default browser is a per-user setting stored in each user's registry hive
    under UserChoice, so this script loads each profile's NTUSER.DAT hive
    directly (no need to run as the logged-on user).

    IMPORTANT: Set "Run As" to Local System in the PDQ scan profile so the
    script can read other users' registry hives.
#>

# Friendly names for common ProgIds
$progIdMap = @{
    'ChromeHTML'          = 'Google Chrome'
    'MSEdgeHTM'           = 'Microsoft Edge'
    'MSEdgeDHTML'         = 'Microsoft Edge Dev'
    'IE.HTTPS'            = 'Internet Explorer'
    'FirefoxURL'          = 'Mozilla Firefox'
    'FirefoxURL-308046B0AF4A39CB' = 'Mozilla Firefox'
    'BraveHTML'           = 'Brave'
    'OperaStable'         = 'Opera'
    'VivaldiHTM'          = 'Vivaldi'
    'SafariHTML'          = 'Safari'
    'AppXq0fevzme2pys62n3e0fbqa7peapykr8v' = 'Microsoft Edge (UWP)'
    'YandexHTML'          = 'Yandex'
    'ArcHTML'             = 'Arc'
}

# --- Detect installed browsers (machine-wide) ---
$installedBrowsers = [System.Collections.Generic.List[string]]::new()
$startMenuKey = 'HKLM:\SOFTWARE\Clients\StartMenuInternet'
if (Test-Path $startMenuKey) {
    Get-ChildItem $startMenuKey -ErrorAction SilentlyContinue | ForEach-Object {
        $name = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).'(default)'
        if (-not $name) { $name = $_.PSChildName }
        if ($name) { $installedBrowsers.Add($name) }
    }
}
$installedBrowserList = ($installedBrowsers | Sort-Object -Unique) -join '; '

# --- Build a list of user profiles to inspect ---
$profileList = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
    Where-Object { -not $_.Special -and $_.LocalPath -notmatch '\\(systemprofile|LocalService|NetworkService)$' }

$results = foreach ($profile in $profileList) {

    $username = Split-Path $profile.LocalPath -Leaf
    $sid      = $profile.SID
    $hivePath = Join-Path $profile.LocalPath 'NTUSER.DAT'
    $loaded   = $false
    $regRoot  = "Registry::HKEY_USERS\$sid"

    # If the hive isn't already mounted (user not logged in), mount it temporarily
    if (-not (Test-Path $regRoot)) {
        if (Test-Path $hivePath) {
            $null = reg.exe load "HKU\$sid" "$hivePath" 2>&1
            if ($LASTEXITCODE -eq 0) { $loaded = $true } else { continue }
        } else {
            continue
        }
    }

    try {
        $userChoicePath = "$regRoot\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice"
        $progId = (Get-ItemProperty -Path $userChoicePath -ErrorAction SilentlyContinue).ProgId

        $browser = if ($progId -and $progIdMap.ContainsKey($progId)) {
            $progIdMap[$progId]
        } elseif ($progId) {
            $progId  # Unknown — return the raw ProgId so you can still see it
        } else {
            $null
        }

        [PSCustomObject]@{
            UserName        = $username
            SID             = $sid
            DefaultBrowser  = $browser
            RawProgId       = $progId
            LastUseTime     = $profile.LastUseTime
            InstalledBrowsers = $installedBrowserList
        }
    }
    finally {
        if ($loaded) {
            [gc]::Collect()  # Release any open registry handles before unloading
            $null = reg.exe unload "HKU\$sid" 2>&1
        }
    }
}

$results