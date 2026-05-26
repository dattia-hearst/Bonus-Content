<#
.SYNOPSIS
    Returns all members of the local Administrators group.
 
.DESCRIPTION
    Enumerates every member of the built-in local Administrators group
    and returns one row per member as a PSCustomObject.
 
    Useful for auditing privilege sprawl, finding stale accounts, and spotting
    machines where unexpected users or groups have been granted admin rights.
#>


# Set target group to Administrators. Note: you could target the SID to be language agnostic
$AdminGroup = Get-LocalGroup -Name 'Administrators'

# Enumerate through all members of the Administrators group return results as a PSCustomObject 
Get-LocalGroupMember -Group $adminGroup | ForEach-Object {
 
    [PSCustomObject]@{
        MemberName      = $_.Name
        ObjectClass     = [string]$_.ObjectClass
        PrincipalSource = [string]$_.PrincipalSource
        SID             = $_.SID.Value
    }
}