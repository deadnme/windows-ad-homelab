<#
.SYNOPSIS
    Onboards ONE new hire: account, groups, random temporary password.

.DESCRIPTION
    What a help desk tech does for a "New starter" ticket, in one command:
      1. Create the account in the right department OU
      2. Add to the department group (which gives the S: drive + share access)
      3. Set a random one-time password, and force a change at first logon
      4. Print a summary to paste into the ticket
    The random password is shown ONCE. Give it to the manager by phone or in
    person, never in the same email as the username.

.EXAMPLE
    .\Invoke-Onboarding.ps1 -FirstName Liam -LastName Ortiz -Department Sales -Title 'Sales Representative' -Manager rachel.kim
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $FirstName,
    [Parameter(Mandatory)] [string] $LastName,
    [Parameter(Mandatory)] [ValidateSet('Management','Accounting','Sales','Operations','HR','IT')] [string] $Department,
    [Parameter(Mandatory)] [string] $Title,
    [string] $Manager
)

Import-Module ActiveDirectory
$sam = "$FirstName.$LastName".ToLower() -replace '[^a-z0-9.]', ''
if (Get-ADUser -Filter "SamAccountName -eq '$sam'") { throw "$sam already exists. Check for a returning employee before creating a duplicate." }

# 16 random characters from a set that always meets complexity rules
$chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!@#$%*?'
$pwdText = -join ($chars | ForEach-Object { $_[(Get-Random -Maximum $_.Length)] })        # one of each type
$pwdText += -join (1..12 | ForEach-Object { ($chars -join '')[(Get-Random -Maximum ($chars -join '').Length)] })

$params = @{
    Name = "$FirstName $LastName"; GivenName = $FirstName; Surname = $LastName
    SamAccountName = $sam; UserPrincipalName = "$sam@harborpoint.internal"
    DisplayName = "$FirstName $LastName"; Title = $Title; Department = $Department
    Company = 'Harbor Point Accounting'
    Path = "OU=$Department,OU=Users,OU=HarborPoint,$((Get-ADDomain).DistinguishedName)"
    AccountPassword = (ConvertTo-SecureString $pwdText -AsPlainText -Force)
    ChangePasswordAtLogon = $true; Enabled = $true
}
if ($Manager) { $params.Manager = (Get-ADUser $Manager).DistinguishedName }

if ($PSCmdlet.ShouldProcess($sam, 'Create and onboard user')) {
    New-ADUser @params
    Add-ADGroupMember "GG_$Department" -Members $sam
    [pscustomobject]@{
        Username      = "HARBORPOINT\$sam"
        Email_UPN     = "$sam@harborpoint.internal"
        Department    = $Department
        Groups        = (Get-ADPrincipalGroupMembership $sam).Name -join ', '
        TempPassword  = $pwdText
        MustChangePwd = $true
    } | Format-List
}
