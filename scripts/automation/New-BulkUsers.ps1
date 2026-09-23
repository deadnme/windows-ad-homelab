<#
.SYNOPSIS
    Creates AD user accounts in bulk from a CSV file.

.DESCRIPTION
    CSV columns: FirstName, LastName, Department, Title
    For each row it:
      - builds the username as first.last (lower case)
      - skips anyone who already exists (safe to run twice)
      - creates the user in HarborPoint\Users\<Department>
      - adds them to the department group GG_<Department>
      - forces a password change at first logon

    Supports -WhatIf: shows what WOULD happen without changing anything.
    Always run with -WhatIf first when touching many accounts.

.EXAMPLE
    .\New-BulkUsers.ps1 -CsvPath .\new-hires.csv -WhatIf
    .\New-BulkUsers.ps1 -CsvPath .\new-hires.csv
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $CsvPath,
    [string] $TempPassword = 'Welcome!2026'   # lab-only default
)

Import-Module ActiveDirectory
$root = "OU=Users,OU=HarborPoint,$((Get-ADDomain).DistinguishedName)"
$pwd  = ConvertTo-SecureString $TempPassword -AsPlainText -Force

foreach ($u in Import-Csv $CsvPath) {
    $sam = "$($u.FirstName).$($u.LastName)".ToLower() -replace '[^a-z0-9.]', ''
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'") {
        Write-Warning "$sam already exists - skipped"
        continue
    }
    if ($PSCmdlet.ShouldProcess($sam, "Create user in $($u.Department)")) {
        New-ADUser -Name "$($u.FirstName) $($u.LastName)" `
            -GivenName $u.FirstName -Surname $u.LastName `
            -SamAccountName $sam -UserPrincipalName "$sam@harborpoint.internal" `
            -DisplayName "$($u.FirstName) $($u.LastName)" `
            -Title $u.Title -Department $u.Department -Company 'Harbor Point Accounting' `
            -Path "OU=$($u.Department),$root" `
            -AccountPassword $pwd -ChangePasswordAtLogon $true -Enabled $true
        Add-ADGroupMember "GG_$($u.Department)" -Members $sam
        Write-Host "Created $sam ($($u.Department))"
    }
}
