<#
.SYNOPSIS
    Reports enabled user accounts that haven't logged on in N days (or ever).

.DESCRIPTION
    Stale accounts are a security risk: an old account nobody watches is a
    great target for an attacker. Many companies run a report like this
    monthly and disable anything unused for 90 days.

    LastLogonDate comes from lastLogonTimestamp, which AD only updates
    about every 9-14 days. That's fine for a "90 days" report, but don't use
    it to answer "did they log on this morning?".

.EXAMPLE
    .\Get-StaleAccounts.ps1                      # 90 days, show on screen
    .\Get-StaleAccounts.ps1 -Days 30 -CsvPath C:\ITLogs\stale.csv
#>
param(
    [int] $Days = 90,
    [string] $CsvPath
)

Import-Module ActiveDirectory
$cutoff = (Get-Date).AddDays(-$Days)

$stale = Get-ADUser -Filter 'Enabled -eq $true' -Properties LastLogonDate, WhenCreated, Department, PasswordLastSet |
    Where-Object {
        # Never logged on AND the account is older than the cutoff, OR last logon before the cutoff
        ($null -eq $_.LastLogonDate -and $_.WhenCreated -lt $cutoff) -or
        ($_.LastLogonDate -and $_.LastLogonDate -lt $cutoff)
    } |
    Select-Object Name, SamAccountName, Department,
        @{n='LastLogon'; e={ if ($_.LastLogonDate) { $_.LastLogonDate } else { 'Never' } }},
        WhenCreated, PasswordLastSet

if ($CsvPath) { $stale | Export-Csv $CsvPath -NoTypeInformation; Write-Host "Saved $($stale.Count) rows to $CsvPath" }
$stale | Format-Table -AutoSize
