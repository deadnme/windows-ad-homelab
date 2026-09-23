<#
.SYNOPSIS
    Offboards a leaver: disable, scramble password, remove groups, move to Disabled Users.

.DESCRIPTION
    Why not just DELETE the account? Because deleting loses its SID (security ID).
    Files they owned, audit logs and mailbox data then point to an unknown
    "S-1-5-21-..." instead of a name. Companies disable first and delete
    later (e.g. after 30-90 days), once the manager confirms nothing is needed.

    Steps:
      1. Disable the account (they can't log in any more)
      2. Set a random password (kills any saved/cached password)
      3. Save their group list to a CSV (so it can be restored if HR made a mistake)
      4. Remove them from every group except Domain Users
      5. Stamp the description with the date and ticket number
      6. Move them to HarborPoint\Disabled Users

.EXAMPLE
    .\Invoke-Offboarding.ps1 -SamAccountName diego.santos -Ticket HD-1042
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $SamAccountName,
    [Parameter(Mandatory)] [string] $Ticket,
    [string] $LogFolder = 'C:\ITLogs\Offboarding'
)

Import-Module ActiveDirectory
$user   = Get-ADUser $SamAccountName -Properties MemberOf, Description
$target = "OU=Disabled Users,OU=HarborPoint,$((Get-ADDomain).DistinguishedName)"
$groups = $user.MemberOf | Get-ADGroup     # Domain Users is the "primary group", so it's not in MemberOf

if ($PSCmdlet.ShouldProcess($SamAccountName, "Offboard ($Ticket)")) {
    New-Item $LogFolder -ItemType Directory -Force | Out-Null
    $groups | Select-Object @{n='User';e={$SamAccountName}}, Name, DistinguishedName |
        Export-Csv "$LogFolder\$SamAccountName-groups-$(Get-Date -Format yyyyMMdd).csv" -NoTypeInformation

    Disable-ADAccount $user
    $random = 'Aa1!' + -join ((33..126) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
    Set-ADAccountPassword $user -Reset -NewPassword (ConvertTo-SecureString $random -AsPlainText -Force)
    foreach ($g in $groups) { Remove-ADGroupMember $g -Members $user -Confirm:$false }
    Set-ADUser $user -Description "Disabled $(Get-Date -Format yyyy-MM-dd) - $Ticket"
    Move-ADObject $user -TargetPath $target

    Get-ADUser $SamAccountName -Properties Description, MemberOf |
        Format-List Name, Enabled, Description, DistinguishedName, @{n='Groups left';e={$_.MemberOf.Count}}
    Write-Host "Group list saved to $LogFolder"
}
