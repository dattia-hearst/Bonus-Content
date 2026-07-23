$Name = 'LGElectronics.LGMonitorApp'
 
$pkg = Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue |
    Select-Object -First 1
 
[PSCustomObject]@{
    Name      = $Name
    Installed = [bool]$pkg
    Version   = $pkg.Version
}