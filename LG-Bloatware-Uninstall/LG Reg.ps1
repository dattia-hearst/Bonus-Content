# Prevent device metadata retrieval from the network
$regPath   = 'HKLM:\Software\Policies\Microsoft\Windows\Device Metadata'
$valueName = 'PreventDeviceMetadataFromNetwork'
$valueData = 1

# Create the key if it doesn't exist
if (-not (Test-Path -Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
    Write-Output "Created key: $regPath"
}

# Set the value (creates it if missing, overwrites if present)
New-ItemProperty -Path $regPath -Name $valueName -Value $valueData -PropertyType DWord -Force | Out-Null
Write-Output "Set $valueName = $valueData"