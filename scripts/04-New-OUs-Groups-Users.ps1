<#
.SYNOPSIS
    Builds Harbor Point's OU structure, security groups and 20 user accounts.

.DESCRIPTION
    OU (Organizational Unit) = a folder inside AD. We use OUs to organise
    objects AND to target Group Policy (a GPO linked to an OU applies to
    everything inside it).

    HarborPoint
    ├── Users
    │   ├── Management, Accounting, Sales, Operations, HR, IT
    ├── Groups
    ├── Computers
    │   └── Workstations
    └── Disabled Users      <- leavers go here (see offboarding script)

    Groups follow the AGDLP rule (Accounts -> Global groups -> Domain Local
    groups -> Permissions):
      GG_Accounting        "who is in Accounting"          (Global group)
      DL_Share_Accounting  "who may change the Accounting share" (Domain Local)
      GG_Accounting is a member of DL_Share_Accounting, and ONLY the DL
      group appears on the folder's permissions. Staff join/leave by
      changing GG membership - nobody touches folder permissions again.

    Usernames are first.last (e.g. priya.patel). Everyone starts with the
    same LAB-ONLY temporary password and must change it at first logon.
#>

Import-Module ActiveDirectory
$domain  = (Get-ADDomain).DistinguishedName        # DC=harborpoint,DC=internal
$root    = "OU=HarborPoint,$domain"
$depts   = 'Management','Accounting','Sales','Operations','HR','IT'
$csv     = Join-Path $PSScriptRoot 'users.csv'

# --- OUs ---------------------------------------------------------------------
# ProtectedFromAccidentalDeletion is on by default: you can't delete the OU
# until you untick it. That saves many admins from a very bad day.
New-ADOrganizationalUnit -Name HarborPoint -Path $domain
'Users','Groups','Computers','Disabled Users','Admin Accounts' | ForEach-Object {
    New-ADOrganizationalUnit -Name $_ -Path $root
}
New-ADOrganizationalUnit -Name Workstations -Path "OU=Computers,$root"
$depts | ForEach-Object { New-ADOrganizationalUnit -Name $_ -Path "OU=Users,$root" }

# New computers joining the domain normally land in the generic
# "Computers" container, where OU-linked GPOs can't reach them.
# redircmp makes Workstations the default instead.
redircmp "OU=Workstations,OU=Computers,$root"

# --- Groups ------------------------------------------------------------------
$groups = "OU=Groups,$root"
foreach ($d in $depts) {
    New-ADGroup -Name "GG_$d" -GroupScope Global -GroupCategory Security -Path $groups `
        -Description "All staff in the $d department"
    New-ADGroup -Name "DL_Share_$d" -GroupScope DomainLocal -GroupCategory Security -Path $groups `
        -Description "Modify access to \\DC01\$d"
    Add-ADGroupMember "DL_Share_$d" -Members "GG_$d"
}
# Everyone gets the Public share
New-ADGroup -Name DL_Share_Public -GroupScope DomainLocal -GroupCategory Security -Path $groups `
    -Description 'Modify access to \\DC01\Public'
Add-ADGroupMember DL_Share_Public -Members 'Domain Users'

# --- Users -------------------------------------------------------------------
# The same bulk-import script IT uses for new hires later on.
& "$PSScriptRoot\automation\New-BulkUsers.ps1" -CsvPath $csv

# The two IT staff also get admin rights. Real companies give admins a
# SEPARATE account (e.g. adm.ethan.brooks) so their everyday account can't
# be used to take over the domain if it gets phished.
# Admin accounts live in their OWN OU, outside HarborPoint\Users. The help
# desk delegation below covers the Users OU - if admin accounts sat in there,
# the help desk could reset a Domain Admin's password and become one.
# (I made exactly that mistake first - see docs/09 ticket HD-1002.)
foreach ($it in 'ethan.brooks','maya.singh') {
    $u = Get-ADUser $it
    New-ADUser -Name "ADM $($u.Name)" -SamAccountName "adm.$it" `
        -UserPrincipalName "adm.$it@harborpoint.internal" `
        -Path "OU=Admin Accounts,$root" -Description "Admin account for $($u.Name)" `
        -AccountPassword (ConvertTo-SecureString 'HarborLab!2026' -AsPlainText -Force) -Enabled $true
}
Add-ADGroupMember 'Domain Admins' -Members 'adm.ethan.brooks'
# The help desk tech gets only what they need (least privilege): reset
# passwords and unlock accounts in the staff OUs. Delegated below.
New-ADGroup -Name GG_HelpDesk -GroupScope Global -GroupCategory Security -Path $groups `
    -Description 'Can reset passwords and unlock accounts'
Add-ADGroupMember GG_HelpDesk -Members 'adm.maya.singh'

# Delegation = the "Delegation of Control Wizard" done with dsacls:
#   CA  "Reset Password" extended right on user objects
#   RPWP read/write lockoutTime (unlock) and pwdLastSet (force change at logon)
$usersOU = "OU=Users,$root"
dsacls $usersOU /I:S /G "HARBORPOINT\GG_HelpDesk:CA;Reset Password;user" | Out-Null
dsacls $usersOU /I:S /G "HARBORPOINT\GG_HelpDesk:RPWP;lockoutTime;user" | Out-Null
dsacls $usersOU /I:S /G "HARBORPOINT\GG_HelpDesk:RPWP;pwdLastSet;user" | Out-Null

Get-ADUser -Filter * -SearchBase "OU=Users,$root" -Properties Department |
    Sort-Object Department, Name | Format-Table Name, SamAccountName, Department -AutoSize
