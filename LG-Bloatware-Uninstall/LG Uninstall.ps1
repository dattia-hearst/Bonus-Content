$Name = 'LGElectronics.LGMonitorApp'
 
Get-AppxPackage -AllUsers -Name $Name | Remove-AppxPackage -AllUsers
 
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $Name | Remove-AppxProvisionedPackage -Online