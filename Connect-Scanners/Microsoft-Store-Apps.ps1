<#
.SYNOPSIS
    PDQ Connect PowerShell scanner - Appx / MSIX package inventory.
 
.DESCRIPTION
    Returns one row per installed Appx/MSIX package as PSCustomObjects for the
    PDQ Connect PowerShell scanner.
 
    Filtering strategy (tune in the Configuration region):
      * Drop frameworks, resource/language packs, and runtime "plumbing".
      * Drop SignatureKind = System. On modern Windows 11 the in-box apps
        worth tracking (ClipChamp, Sticky Notes, Bing Weather, etc.) are
        Store/Developer signed; the System-signed set is OS components and
        shell experiences (including the GUID-named packages).
      * Drop NonRemovable packages - if it can't be uninstalled there's no
        action to take. Secondary net (NonRemovable doesn't always populate).
      * Drop a small denylist of codecs / media extensions and known system
        enhancements (Store-signed, so the System filter misses them).
      * $AlwaysInclude pins specific packages back in regardless of filters.
 
    Per-user reporting:
      * Aggregates per-user installs into ONE row per package.
      * InstalledUserCount and InstalledForUsers both honor $UserSidRegex, so
        they only reflect real interactive profiles (S-1-5-21-*) and stay in
        sync. System/service accounts are excluded.
      * InstalledForUsers is a comma-separated list of resolved profile names,
        capped at $MaxUsersListed (extras collapse to "+N more").
 
    Other behaviors:
      * Collapses architecture variants of the same package into one row.
      * Casts every enum (Architecture, SignatureKind, InstallState) to a
        string so it serializes predictably.
      * Fails gracefully if the Appx subsystem is unavailable, and appends a
        [TRUNCATED] sentinel row if the result still exceeds the cap. Both
        messages ride in the PackageName field.
 
    Runs in SYSTEM context under the PDQ Connect scanner (required for
    Get-AppxPackage -AllUsers).
#>
 
#region Configuration ---------------------------------------------------------
 
# Hard row cap for the PDQ Connect scanner.
$MaxRows = 100
 
# SignatureKinds to drop. System = OS components / shell experiences.
$DropSignatureKinds = @('System')
 
# Drop packages flagged as non-removable (can't be uninstalled = no action).
$DropIfNonRemovable = $true
 
# Package-name regexes to KEEP even if a filter above would have dropped them.
# e.g. '^Microsoft\.SecHealthUI$' to always surface Windows Security.
$AlwaysInclude = @()
 
# Runtime/plumbing + codec/extension prefixes. These are never user-facing
# "apps". Add lines to suppress more noise without touching the logic.
$ExcludePattern = @(
    '^Microsoft\.VCLibs'
    '^Microsoft\.NET\.'
    '^Microsoft\.UI\.Xaml'
    '^Microsoft\.Services\.Store\.Engagement'
    '^Microsoft\.WindowsAppRuntime'
    '^Microsoft\.WinAppRuntime'
    '^Microsoft\.DirectX'
    '^Microsoft\.Advertising\.Xaml'
    # Codecs / media extensions - Store-signed, so the System filter misses them
    '\.WebpImageExtension$'
    '\.HEIFImageExtension$'
    '\.HEVCVideoExtension'
    '\.VP9VideoExtensions$'
    '\.WebMediaExtensions$'
    '\.RawImageExtension$'
    '\.AV1VideoExtension$'
    '\.MPEG2VideoExtension$'
    # System enhancement, not an app
    '^Microsoft\.ApplicationCompatibilityEnhancements$'
) -join '|'
 
# Matches real interactive-user SIDs (excludes SYSTEM, service, _Classes).
# Both the user count and the profile list honor this, so they stay in sync.
$UserSidRegex = '^S-1-5-21-\d+-\d+-\d+-\d+$'
 
# Max profile names to list in InstalledForUsers (the true total is always in
# InstalledUserCount); extras collapse to "+N more".
$MaxUsersListed = 15
 
#endregion --------------------------------------------------------------------
 
#region Helpers ---------------------------------------------------------------
 
function Resolve-Sid {
    param([string]$Sid)
    try {
        (New-Object System.Security.Principal.SecurityIdentifier($Sid)).
            Translate([System.Security.Principal.NTAccount]).Value
    }
    catch {
        $Sid   # Fall back to the raw SID (deleted/orphaned profiles, etc.).
    }
}
 
# Fixed-schema row builder so EVERY object PDQ receives has the same columns.
function New-ScanRow {
    param(
        [string]$PackageName,
        [string]$Version,
        [string]$Publisher,
        [string]$Architecture,
        [string]$SignatureKind,
        [int]   $InstalledUserCount,
        [string]$InstalledForUsers
    )
    [pscustomobject]@{
        PackageName        = $PackageName
        Version            = $Version
        Publisher          = $Publisher
        Architecture       = $Architecture
        SignatureKind      = $SignatureKind
        InstalledUserCount = $InstalledUserCount
        InstalledForUsers  = $InstalledForUsers
    }
}
 
#endregion --------------------------------------------------------------------
 
#region Collect ---------------------------------------------------------------
 
$results = [System.Collections.Generic.List[object]]::new()
 
try {
    $packages = Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
        $keep = $true
        if     ($_.IsFramework -or $_.IsResourcePackage)                     { $keep = $false }
        elseif ($_.Name -match $ExcludePattern)                              { $keep = $false }
        elseif ($DropSignatureKinds -contains $_.SignatureKind.ToString())   { $keep = $false }
        elseif ($DropIfNonRemovable -and ($_.NonRemovable -eq $true))        { $keep = $false }
 
        # Allowlist override - pin specific packages back in.
        if (-not $keep -and $AlwaysInclude.Count -gt 0) {
            foreach ($inc in $AlwaysInclude) {
                if ($_.Name -match $inc) { $keep = $true; break }
            }
        }
        $keep
    }
}
catch {
    New-ScanRow -PackageName "Error: $($_.Exception.Message)" -InstalledUserCount 0
    return
}
 
# Group by Name so architecture variants collapse to a single row per app.
foreach ($group in ($packages | Group-Object Name)) {
 
    # Representative package = highest version in the group (version-safe sort).
    $pkg = $group.Group |
        Sort-Object { try { [version]$_.Version } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1
 
    # Distinct real-user SIDs with the package actually installed (deduped
    # across architecture variants; SID parsed from each entry's string form).
    $sids = @($group.Group.PackageUserInformation |
        Where-Object { $_.InstallState.ToString() -eq 'Installed' } |
        ForEach-Object { if ("$_" -match '(S-1-[0-9-]+)') { $matches[1] } } |
        Where-Object { $_ -match $UserSidRegex } |
        Select-Object -Unique)
 
    # Resolve SIDs to profile/account names for the InstalledForUsers list.
    $names = @($sids | ForEach-Object { Resolve-Sid $_ } | Sort-Object)
 
    $userList = if ($names.Count -gt $MaxUsersListed) {
        (($names | Select-Object -First $MaxUsersListed) -join ', ') +
            ", +$($names.Count - $MaxUsersListed) more"
    }
    else {
        $names -join ', '
    }
 
    # Trim the publisher DN down to the common name where possible.
    $publisher = if ($pkg.Publisher -match 'CN=([^,]+)') { $matches[1].Trim() }
                 else { $pkg.Publisher }
 
    $results.Add( (New-ScanRow `
        -PackageName        $pkg.Name `
        -Version            ([string]$pkg.Version) `
        -Publisher          $publisher `
        -Architecture       $pkg.Architecture.ToString() `
        -SignatureKind      $pkg.SignatureKind.ToString() `
        -InstalledUserCount $sids.Count `
        -InstalledForUsers  $userList) )
}
 
#endregion --------------------------------------------------------------------
 
#region Output (respect the 100-row cap) --------------------------------------
 
$sorted = $results | Sort-Object PackageName
 
if ($sorted.Count -eq 0) {
    New-ScanRow -PackageName 'None - no matching packages found' -InstalledUserCount 0
}
elseif ($sorted.Count -gt $MaxRows) {
    $omitted = $sorted.Count - ($MaxRows - 1)
    $sorted | Select-Object -First ($MaxRows - 1)
    New-ScanRow -PackageName "[TRUNCATED] $omitted package(s) omitted - tighten the filters" -InstalledUserCount 0
}
else {
    $sorted
}
 
#endregion --------------------------------------------------------------------