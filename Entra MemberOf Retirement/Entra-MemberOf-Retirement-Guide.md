# Microsoft Entra ID: MemberOf Retirement Guide
### Deadline: November 3, 2026

> **ACTION REQUIRED** — Dynamic groups, dynamic administrative units, and entitlement management policies using `user.memberOf` rules will stop updating after November 3, 2026. Membership freezes at whatever state it's in on that date.

---

## What's Happening

Microsoft is retiring the `MemberOf` rule operator from Entra ID dynamic membership rules. If any of your dynamic groups, dynamic AUs, or entitlement management auto-assignment policies use a rule like:

```
user.memberOf -any (group.objectId -in ['<guid>'])
```

...those rules stop processing on November 3rd. Membership doesn't get deleted — it freezes. No new members are added. No stale members are removed.

**Why Microsoft is doing this:** MemberOf was always a public preview feature marked "not recommended for production." Microsoft's stated reason for retirement: a single MemberOf rule can degrade dynamic membership processing for the **entire tenant**, not just the affected group. It's a compute cost problem at scale.

**What this doesn't affect:** On-prem AD groups synced via Entra Connect are NOT impacted. This only applies to dynamic membership rules evaluated by Entra ID itself.

---

## What Breaks If You Do Nothing

- New hires in a department group don't automatically receive M365 licenses
- Offboarded users retain access to SharePoint sites, Teams, and apps
- Conditional Access policies stop reflecting current group membership — **security gap**
- Entitlement Management stops adding/removing access package assignments
- Group-based licensing drifts — unlicensed or over-licensed users accumulate
- Dynamic AU scope goes stale — admins may manage the wrong users

---

## Step 1: Find Your Exposure

Run these three queries before doing anything else.

### Connect

```powershell
Connect-MgGraph -Scopes "Group.Read.All", "AdministrativeUnit.Read.All", "EntitlementManagement.Read.All"
```

### Find affected dynamic groups

```powershell
$dynamicGroups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'DynamicMembership')" -All -Property DisplayName,MembershipRule,Id

$affectedGroups = $dynamicGroups | Where-Object { $_.MembershipRule -match "memberOf" }

$affectedGroups | Select-Object DisplayName, Id, MembershipRule | Format-Table -AutoSize
```

### Find affected dynamic administrative units

```powershell
$aus = Get-MgAdministrativeUnit -All -Property DisplayName,MembershipRule,Id,MembershipType

$affectedAUs = $aus | Where-Object { $_.MembershipRule -match "memberOf" }

$affectedAUs | Select-Object DisplayName, Id, MembershipRule | Format-Table -AutoSize
```

### Find affected entitlement management policies

```powershell
$policies = Get-MgEntitlementManagementAssignmentPolicy -All

$policies | Where-Object { $_.AutoAssignment -ne $null } | Select-Object DisplayName, Id
```

> **Community resource:** A pre-built audit script is available at [github.com/admindroid-community/powershell-scripts](https://github.com/admindroid-community/powershell-scripts) — run this to get a full tenant exposure report.

---

## Step 2: Remediate — Two Paths

### Path A — Replace with a supported dynamic rule

If the MemberOf rule was a proxy for a user attribute you already have, replace it directly. This is the cleanest fix and keeps the group dynamic.

| Old MemberOf use case | Replacement rule |
|---|---|
| Department group membership | `user.department -eq "Engineering"` |
| Role/job title | `user.jobTitle -eq "Manager"` |
| Contractor vs FTE | `user.extensionAttribute1 -eq "contractor"` |
| Location | `user.city -eq "Seattle"` |
| License-based | `user.assignedPlans` with service plan GUID |

**Licensing example — replace MemberOf with assignedPlans:**

```
user.assignedPlans -any (
  assignedPlan.servicePlanId -eq "e212cbc7-0961-4c40-9825-01117710dcb1"
  -and assignedPlan.capabilityStatus -eq "Enabled"
)
```

Get service plan GUIDs from: [learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference](https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference)

> **Prerequisite:** User attributes must be populated and accurate. If your HR system doesn't consistently set the `department` attribute in AD, attribute-based rules will be unreliable. Audit attribute quality before committing to this path.

---

### Path B — Convert to assigned group + Graph API sync

When no attribute covers your use case — you genuinely need "members of Group A → Group B" — convert the dynamic group to assigned membership and automate sync via Graph API.

**Step 1 — Read source group membership:**

```powershell
Connect-MgGraph -Scopes "Group.Read.All", "GroupMember.ReadWrite.All"

$sourceGroupId = "<source-group-object-id>"
$sourceMembers = Get-MgGroupMember -GroupId $sourceGroupId -All
$sourceMemberIds = $sourceMembers.Id
```

**Step 2 — Read current target group membership:**

```powershell
$targetGroupId = "<target-group-object-id>"
$targetMembers = Get-MgGroupMember -GroupId $targetGroupId -All
$targetMemberIds = $targetMembers.Id
```

**Step 3 — Add missing members:**

```powershell
$toAdd = $sourceMemberIds | Where-Object { $_ -notin $targetMemberIds }

foreach ($userId in $toAdd) {
  $body = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$userId" }
  New-MgGroupMemberByRef -GroupId $targetGroupId -BodyParameter $body
  Write-Host "Added: $userId"
}
```

**Step 4 — Remove stale members:**

```powershell
$toRemove = $targetMemberIds | Where-Object { $_ -notin $sourceMemberIds }

foreach ($userId in $toRemove) {
  Remove-MgGroupMemberByRef -GroupId $targetGroupId -DirectoryObjectId $userId
  Write-Host "Removed: $userId"
}
```

> **Scheduling:** Run this on a cadence that matches your SLA. Every 15–30 minutes works for most licensing and access scenarios. For Conditional Access-sensitive groups, run it tighter. Azure Automation Runbooks are the easiest hosting option — no on-prem infrastructure required.

---

## Common Scenarios

### M365 Licensing
**Situation:** A licensing group used MemberOf to assign licenses based on department group membership.

- **Option 1:** Replace with `user.department` or `user.extensionAttribute`. Best if attributes are accurate.
- **Option 2:** Convert to assigned group + Graph sync script on schedule.
- **Option 3:** Use `user.assignedPlans` if you're licensing based on whether users already have a specific service plan (common for E3 → E5 upgrades).

### Intune App / Policy Assignment
**Situation:** A dynamic group for Intune targeting inherited membership via MemberOf from a department or role group.

- Replace with user attribute rules (`department`, `extensionAttribute`, `jobTitle`), or convert to assigned + Graph sync. For Intune, syncing every 30 minutes is typically close enough for app deployment.

### SharePoint / Teams Access
**Situation:** An M365 group's membership was driven by MemberOf from a security group.

- Graph sync is the primary option here — M365 groups don't support dynamic membership the same way security groups do. Convert to assigned, run sync on schedule.

### Conditional Access Targeting
**Situation:** A CA policy was scoped to a dynamic group using MemberOf.

- **Fix this first** — a frozen CA group is a security issue, not just an operational inconvenience. Replace with attribute-based rules where possible. If using Graph sync, run it frequently and validate before November 3rd.

### Dynamic Administrative Units
**Situation:** A dynamic AU used MemberOf to scope admin roles.

- Replace rule with a supported operator, or convert to assigned + Graph sync. Validate admin scope after any changes — stale scope is an audit finding.

---

## Priority Order

1. **Conditional Access groups** — security risk if frozen
2. **Licensing groups** — compliance and cost exposure
3. **Intune / app assignment** — operational impact
4. **Teams / SharePoint access** — user experience impact
5. **Administrative Units** — governance / audit risk

---

## Reference Links

- [Microsoft MC1448379 — Message Center Notice](https://admin.microsoft.com/adminportal/home#/MessageCenter)
- [Microsoft Docs — Migrate before the preview ends](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-rule-member-of#migrate-before-the-preview-ends)
- [Service Plan GUIDs reference](https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference)
- [Admindroid community audit scripts](https://github.com/admindroid-community/powershell-scripts)

---

*Source: r/sysadmin community thread + Microsoft MC1448379 | Last updated August 2026*
