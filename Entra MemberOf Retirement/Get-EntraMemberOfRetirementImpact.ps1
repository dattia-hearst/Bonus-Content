#region setup

# Install once, if needed
# Install-Module Microsoft.Graph -Scope CurrentUser

# Least-privileged read permissions for all three surfaces
Connect-MgGraph -Scopes @(
    "Group.Read.All"
    "AdministrativeUnit.Read.All"
    "EntitlementManagement.Read.All"
)
Write-Verbose "Connected to $(Get-MGContext | Select-Object Account, TenantID)"

$MemberOfPattern = '(?i)memberOf'
$Findings = [System.Collections.Generic.List[object]]::new()

#endregion setup


#Region groups
$Groups = Get-MgGroup -All -Property @(
    "id"
    "displayName"
    "groupTypes"
    "membershipRule"
    "membershipRuleProcessingState"
)

foreach ($Group in $Groups) {
    if ($Group.MembershipRule -match $MemberOfPattern) {
        [void]$Findings.Add([pscustomobject]@{
            Surface = "Dynamic group"
            Name    = $Group.DisplayName
            Parent  = $null
            Id      = $Group.Id
            State   = $Group.MembershipRuleProcessingState
            Rule    = $Group.MembershipRule
        })
    }
}
#endregion groups

#region Dynamic Administrative Units 
$AdministrativeUnits = Get-MgDirectoryAdministrativeUnit -All -Property @(
    "id"
    "displayName"
    "membershipType"
    "membershipRule"
    "membershipRuleProcessingState"
)

foreach ($AdministrativeUnit in $AdministrativeUnits) {
    if ($AdministrativeUnit.MembershipRule -match $MemberOfPattern) {
        [void]$Findings.Add([pscustomobject]@{
            Surface = "Dynamic Administrative Unit"
            Name    = $AdministrativeUnit.DisplayName
            Parent  = $null
            Id      = $AdministrativeUnit.Id
            State   = $AdministrativeUnit.MembershipRuleProcessingState
            Rule    = $AdministrativeUnit.MembershipRule
        })
    }
}
#endregion Dynamic Administrative Units 

#region Entitlement Management Auto Assignment Policies 
# you wo'nt have these if you don't have an Entra ID Governance Subscription (spoiler: we don't)

$PolicyUri = @"
https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$expand=accessPackage&`$top=100
"@ -replace "`r|`n", ""

$Policies = @()

while ($PolicyUri) {
    $Page = Invoke-MgGraphRequest -Method GET -Uri $PolicyUri -OutputType PSObject

    $Policies += @($Page.value)
    $PolicyUri = $Page.'@odata.nextLink'
}

foreach ($Policy in $Policies) {
    # automaticRequestSettings only exists on auto-assignment policies
    if ($null -eq $Policy.automaticRequestSettings) {
        continue
    }

    foreach ($Target in @($Policy.specificAllowedTargets)) {
        $TargetType = $Target.'@odata.type'
        $Rule = $Target.membershipRule

        if (
            $TargetType -eq "#microsoft.graph.attributeRuleMembers" -and
            $Rule -match $MemberOfPattern
        ) {
            [void]$Findings.Add([pscustomobject]@{
                Surface = "Entitlement auto-assignment policy"
                Name    = $Policy.displayName
                Parent  = $Policy.accessPackage.displayName
                Id      = $Policy.id
                State   = $null
                Rule    = $Rule
            })
        }
    }
}
#endregion Entitlement Management Auto Assignment Policies 


#region Results

if ($Findings.Count -eq 0) {
    Write-Host "No affected memberOf configurations found." `
        -ForegroundColor Green
}
else {
    $Findings |
        Sort-Object Surface,Name |
        Format-Table Surface,Name,Parent,State,Rule, Id -Wrap
}

#endregion Results
