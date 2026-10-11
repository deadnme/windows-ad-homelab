<#
.SYNOPSIS
    Daily health and audit report for a small Active Directory domain, saved as one HTML file.

.DESCRIPTION
    Run on a domain controller. Checks user and computer accounts (lockouts, expired accounts,
    passwords about to expire, stale accounts, privileged group members), Group Policy links,
    and the domain controller itself (core services, disk space, failed sign-ins, pending reboot,
    last installed update). Each check is marked OK, Info, Warning or Critical, and the report
    opens with a summary so problems are visible at a glance.

    Read-only: the script changes nothing in AD or on the server.

.EXAMPLE
    .\Get-ADHealthReport.ps1
    Writes .\Reports\AD-Health-<date>.html using the default thresholds.

.EXAMPLE
    .\Get-ADHealthReport.ps1 -OutputFolder C:\Reports -StaleDays 60 -PasswordWarnDays 7
#>
#Requires -Modules ActiveDirectory, GroupPolicy
[CmdletBinding()]
param(
    [string]$OutputFolder = (Join-Path $PWD 'Reports'),
    [int]$StaleDays = 90,           # enabled accounts with no sign-in for this long are stale
    [int]$PasswordWarnDays = 14,    # warn about passwords expiring within this many days
    [int]$DiskWarnPercent = 20,
    [int]$DiskCritPercent = 10,
    [int]$EventHours = 24,          # how far back to read the Security log
    [int]$UpdateWarnDays = 45       # warn when no update has been installed for this long
)

$ErrorActionPreference = 'Stop'
$now     = Get-Date
$domain  = Get-ADDomain
$results = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Area, [string]$Title, [string]$Status, [string]$Summary, $Rows = @())
    $results.Add([pscustomobject]@{
        Area = $Area; Title = $Title; Status = $Status; Summary = $Summary; Rows = @($Rows)
    })
}

# Wraps each check so one failure (missing role, no permission) becomes a Critical row
# instead of stopping the whole report.
function Invoke-Check {
    param([string]$Area, [string]$Title, [scriptblock]$Body)
    try { & $Body }
    catch { Add-Check $Area $Title 'Critical' "Check failed: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- Accounts

Invoke-Check 'Accounts' 'Locked-out users' {
    # LockedOut is computed, so it drops accounts whose lockout duration has already passed
    # (Search-ADAccount -LockedOut still lists those until the next sign-in).
    # ponytail: reads every user, fine for small domains; filter on lockoutTime>=1 first if it gets slow.
    $rows = Get-ADUser -Filter * -Properties LockedOut, LockoutTime, BadLogonCount | Where-Object LockedOut |
        Select-Object SamAccountName, Name,
            @{ n = 'LockedSince'; e = { [datetime]::FromFileTime($_.LockoutTime) } }, BadLogonCount
    if ($rows) { Add-Check 'Accounts' 'Locked-out users' 'Warning' "$(@($rows).Count) user(s) locked out." $rows }
    else       { Add-Check 'Accounts' 'Locked-out users' 'OK' 'No users are locked out.' }
}

Invoke-Check 'Accounts' 'Expired accounts' {
    $rows = Search-ADAccount -AccountExpired -UsersOnly | Where-Object Enabled |
        Select-Object SamAccountName, Name, AccountExpirationDate
    if ($rows) { Add-Check 'Accounts' 'Expired accounts' 'Warning' "$(@($rows).Count) enabled account(s) have passed their expiry date and cannot sign in." $rows }
    else       { Add-Check 'Accounts' 'Expired accounts' 'OK' 'No enabled accounts have expired.' }
}

Invoke-Check 'Accounts' 'Passwords expiring soon' {
    $rows = Get-ADUser -Filter 'Enabled -eq $true -and PasswordNeverExpires -eq $false' `
            -Properties 'msDS-UserPasswordExpiryTimeComputed', PasswordLastSet |
        Where-Object { $_.'msDS-UserPasswordExpiryTimeComputed' -gt 0 -and
                       $_.'msDS-UserPasswordExpiryTimeComputed' -lt [long]::MaxValue } |
        ForEach-Object {
            $expires = [datetime]::FromFileTime($_.'msDS-UserPasswordExpiryTimeComputed')
            [pscustomobject]@{
                SamAccountName  = $_.SamAccountName
                Name            = $_.Name
                PasswordLastSet = $_.PasswordLastSet
                Expires         = $expires
                DaysLeft        = [math]::Floor(($expires - $now).TotalDays)
            }
        } |
        Where-Object DaysLeft -le $PasswordWarnDays | Sort-Object DaysLeft
    if ($rows) {
        $expired = @($rows | Where-Object DaysLeft -lt 0).Count
        Add-Check 'Accounts' 'Passwords expiring soon' 'Warning' "$(@($rows).Count) password(s) expire within $PasswordWarnDays days ($expired already expired)." $rows
    }
    else { Add-Check 'Accounts' 'Passwords expiring soon' 'OK' "No passwords expire within $PasswordWarnDays days." }
}

Invoke-Check 'Accounts' 'Passwords set to never expire' {
    $rows = Get-ADUser -Filter 'Enabled -eq $true -and PasswordNeverExpires -eq $true' -Properties PasswordLastSet |
        Select-Object SamAccountName, Name, PasswordLastSet
    if ($rows) { Add-Check 'Accounts' 'Passwords set to never expire' 'Warning' "$(@($rows).Count) enabled account(s) skip the password expiry policy." $rows }
    else       { Add-Check 'Accounts' 'Passwords set to never expire' 'OK' 'Every enabled account follows the password expiry policy.' }
}

# An account is stale if its last sign-in is older than the cutoff, or it has never signed in
# and was created before the cutoff. lastLogonTimestamp replicates every 9-14 days, so a few
# days of drift is normal.
$cutoff = $now.AddDays(-$StaleDays)
function Select-Stale {
    process {
        if (($_.LastLogonDate -and $_.LastLogonDate -lt $cutoff) -or
            (-not $_.LastLogonDate -and $_.whenCreated -lt $cutoff)) { $_ }
    }
}

Invoke-Check 'Accounts' 'Stale user accounts' {
    $rows = Get-ADUser -Filter 'Enabled -eq $true' -Properties LastLogonDate, whenCreated | Select-Stale |
        Select-Object SamAccountName, Name, LastLogonDate, whenCreated
    if ($rows) { Add-Check 'Accounts' 'Stale user accounts' 'Warning' "$(@($rows).Count) enabled user(s) have not signed in for $StaleDays+ days." $rows }
    else       { Add-Check 'Accounts' 'Stale user accounts' 'OK' "Every enabled user has signed in within $StaleDays days (or is newer than that)." }
}

Invoke-Check 'Accounts' 'Stale computer accounts' {
    $rows = Get-ADComputer -Filter 'Enabled -eq $true' -Properties LastLogonDate, whenCreated, OperatingSystem | Select-Stale |
        Select-Object Name, OperatingSystem, LastLogonDate, whenCreated
    if ($rows) { Add-Check 'Accounts' 'Stale computer accounts' 'Warning' "$(@($rows).Count) computer(s) have not contacted the domain for $StaleDays+ days." $rows }
    else       { Add-Check 'Accounts' 'Stale computer accounts' 'OK' "Every enabled computer has contacted the domain within $StaleDays days." }
}

Invoke-Check 'Accounts' 'Disabled users still in groups' {
    # Skip built-in Guest (-501), krbtgt (-502) and DefaultAccount (-503): they ship disabled
    # and in default groups.
    $rows = Get-ADUser -Filter 'Enabled -eq $false' -Properties MemberOf |
        Where-Object { $_.MemberOf -and $_.SID.Value -notmatch '-50[123]$' } |
        Select-Object SamAccountName, Name,
            @{ n = 'Groups'; e = { ($_.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace '^CN=' }) -join ', ' } }
    if ($rows) { Add-Check 'Accounts' 'Disabled users still in groups' 'Warning' "$(@($rows).Count) disabled user(s) keep group memberships; re-enabling them would restore that access." $rows }
    else       { Add-Check 'Accounts' 'Disabled users still in groups' 'OK' 'No disabled users hold group memberships.' }
}

Invoke-Check 'Accounts' 'Privileged group members' {
    # Looked up by well-known SID so the check works on non-English DCs. Enterprise and Schema
    # Admins only exist in the forest root domain, so missing groups are skipped.
    $rootSid = (Get-ADDomain (Get-ADForest).RootDomain).DomainSID.Value
    $sids = "$($domain.DomainSID.Value)-512", "$rootSid-519", "$rootSid-518",
            'S-1-5-32-544', 'S-1-5-32-548', 'S-1-5-32-549', 'S-1-5-32-551'   # Administrators, Account/Server/Backup Operators
    $rows = foreach ($sid in $sids) {
        $g = Get-ADGroup -Filter "SID -eq '$sid'"
        if (-not $g) { continue }
        Get-ADGroupMember -Identity $g -Recursive | Where-Object objectClass -eq 'user' | ForEach-Object {
            $u = Get-ADUser $_ -Properties Enabled, LastLogonDate
            [pscustomobject]@{ Group = $g.Name; SamAccountName = $u.SamAccountName; Enabled = $u.Enabled; LastLogonDate = $u.LastLogonDate }
        }
    }
    $people = @($rows | Select-Object -ExpandProperty SamAccountName -Unique).Count
    Add-Check 'Accounts' 'Privileged group members' 'Info' "$people account(s) are in built-in admin or operator groups. Review that each one still needs it (delegated permissions are not checked)." $rows
}

# ---------------------------------------------------------------- Group Policy

Invoke-Check 'Group Policy' 'Group Policy links' {
    $rows = foreach ($gpo in Get-GPO -All) {
        [xml]$xml = Get-GPOReport -Guid $gpo.Id -ReportType Xml
        $links = @($xml.GPO.LinksTo)
        $problem = $null
        if ($gpo.GpoStatus -eq 'AllSettingsDisabled')                 { $problem = 'All settings disabled' }
        elseif (-not $xml.GPO.LinksTo)                                 { $problem = 'Not linked anywhere' }
        elseif (-not ($links | Where-Object { $_.Enabled -eq 'true' })) { $problem = 'Every link is disabled' }
        if ($problem) {
            [pscustomobject]@{
                GPO     = $gpo.DisplayName
                Problem = $problem
                LinksTo = ($links | Where-Object { $_ } | ForEach-Object { "$($_.SOMPath) (enabled: $($_.Enabled))" }) -join '; '
            }
        }
    }
    if ($rows) { Add-Check 'Group Policy' 'Group Policy links' 'Warning' "$(@($rows).Count) GPO(s) exist but do not apply to anything." $rows }
    else       { Add-Check 'Group Policy' 'Group Policy links' 'OK' 'Every GPO is linked and enabled somewhere.' }
}

# ---------------------------------------------------------------- Domain controller

Invoke-Check 'Server' 'Core services' {
    # DHCP Server is optional (not every DC runs it); the rest must exist on a DC, so a missing
    # one also catches the script being run on a machine that is not a domain controller.
    $rows = foreach ($name in 'NTDS', 'DNS', 'Netlogon', 'Kdc', 'W32Time', 'LanmanServer', 'DHCPServer') {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) { $svc | Select-Object Name, DisplayName, Status, StartType }
        elseif ($name -ne 'DHCPServer') {
            [pscustomobject]@{ Name = $name; DisplayName = ''; Status = 'Not installed'; StartType = '' }
        }
    }
    $down = @($rows | Where-Object { "$($_.Status)" -ne 'Running' })
    if ($down) { Add-Check 'Server' 'Core services' 'Critical' "$($down.Count) core service(s) not running: $($down.Name -join ', ')." $rows }
    else       { Add-Check 'Server' 'Core services' 'OK' "All $(@($rows).Count) core services are running." $rows }
}

Invoke-Check 'Server' 'Disk space' {
    # Size is empty on RAW or locked volumes; skip them rather than divide by zero.
    $rows = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object Size -gt 0 | ForEach-Object {
        $pct = [math]::Round(100 * $_.FreeSpace / $_.Size, 1)
        [pscustomobject]@{
            Drive       = $_.DeviceID
            SizeGB      = [math]::Round($_.Size / 1GB, 1)
            FreeGB      = [math]::Round($_.FreeSpace / 1GB, 1)
            FreePercent = $pct
        }
    }
    $low = @($rows | Sort-Object FreePercent)[0]
    if     ($low.FreePercent -lt $DiskCritPercent) { $s = 'Critical' }
    elseif ($low.FreePercent -lt $DiskWarnPercent) { $s = 'Warning' }
    else                                           { $s = 'OK' }
    Add-Check 'Server' 'Disk space' $s "Lowest free space: $($low.Drive) at $($low.FreePercent)%." $rows
}

Invoke-Check 'Server' 'Failed sign-ins and lockouts' {
    # 4625 = failed logon on this DC, 4771 = Kerberos pre-authentication failed (wrong password
    # anywhere in the domain), 4740 = account locked out. Needs failure auditing turned on.
    $events = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625, 4771, 4740; StartTime = $now.AddHours(-$EventHours) }
    }
    catch { if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw } }

    $rows = $events | ForEach-Object {
        $x = [xml]$_.ToXml()
        $d = @{}; foreach ($n in $x.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
        # 4740 stores the computer the lockout came from in TargetDomainName.
        $src = if ($_.Id -eq 4740) { $d['TargetDomainName'] } else { $d['IpAddress'] -replace '^::ffff:' }
        if ($src -eq '-' -or -not $src) { $src = $d['WorkstationName'] }   # local logons have no IP
        [pscustomobject]@{
            Account = $d['TargetUserName']
            Event   = switch ($_.Id) { 4625 { 'Failed logon' } 4771 { 'Kerberos pre-auth failed' } 4740 { 'Locked out' } }
            Source  = $src
            Time    = $_.TimeCreated
        }
    }
    $grouped = $rows | Group-Object Account, Event | ForEach-Object {
        $first = $_.Group[0]
        [pscustomobject]@{
            Account = $first.Account; Event = $first.Event; Count = $_.Count
            Sources = ($_.Group.Source | Where-Object { $_ } | Sort-Object -Unique) -join ', '
            Latest  = ($_.Group.Time | Sort-Object -Descending)[0]
        }
    } | Sort-Object Count -Descending

    $lockouts = @($rows | Where-Object Event -eq 'Locked out').Count
    if (-not $rows)  { Add-Check 'Server' 'Failed sign-ins and lockouts' 'OK' "No failed sign-ins or lockouts in the last $EventHours hours." }
    elseif ($lockouts) { Add-Check 'Server' 'Failed sign-ins and lockouts' 'Warning' "$(@($rows).Count) event(s) in the last $EventHours hours, including $lockouts lockout(s)." $grouped }
    else             { Add-Check 'Server' 'Failed sign-ins and lockouts' 'Info' "$(@($rows).Count) failed sign-in(s) in the last $EventHours hours, no lockouts." $grouped }
}

Invoke-Check 'Server' 'Pending reboot' {
    $reasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons += 'Windows component servicing' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons += 'Windows Update' }
    if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)) { $reasons += 'Pending file renames' }
    if ($reasons) { Add-Check 'Server' 'Pending reboot' 'Warning' "Restart needed: $($reasons -join ', ')." }
    else          { Add-Check 'Server' 'Pending reboot' 'OK' 'No restart pending.' }
}

Invoke-Check 'Server' 'Windows updates' {
    $rows = Get-HotFix | Where-Object InstalledOn | Sort-Object InstalledOn -Descending |
        Select-Object -First 5 HotFixID, Description, InstalledOn
    $last = @($rows)[0]
    if (-not $last) { Add-Check 'Server' 'Windows updates' 'Warning' 'No installed updates found.'; return }
    $age = [math]::Floor(($now - $last.InstalledOn).TotalDays)
    $s = if ($age -gt $UpdateWarnDays) { 'Warning' } else { 'OK' }
    Add-Check 'Server' 'Windows updates' $s "Last update ($($last.HotFixID)) installed $age day(s) ago." $rows
}

# ---------------------------------------------------------------- HTML report

function ConvertTo-SafeHtml([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }

$os     = Get-CimInstance Win32_OperatingSystem
$uptime = $now - $os.LastBootUpTime
$counts = $results | Group-Object Status -AsHashTable -AsString
$order  = 'Critical', 'Warning', 'Info', 'OK'
$sorted = $results | Sort-Object @{ e = { $order.IndexOf($_.Status) } }, Area, Title
$worst  = @($sorted)[0].Status

$summaryHtml = ($order | ForEach-Object {
    $n = if ($counts -and $counts[$_]) { $counts[$_].Count } else { 0 }
    "<div class='tile $($_.ToLower())'><b>$n</b><span>$_</span></div>"
}) -join "`n"

$checksHtml = ($sorted | ForEach-Object {
    $table = ''
    if ($_.Rows.Count) {
        $table = ($_.Rows | ConvertTo-Html -Fragment | Out-String)
        $open  = if ($_.Status -in 'Critical', 'Warning') { ' open' } else { '' }
        $table = "<details$open><summary>$($_.Rows.Count) row(s)</summary>$table</details>"
    }
    @"
<section class='check'>
  <div class='head'><span class='badge $($_.Status.ToLower())'>$($_.Status)</span>
  <h3>$(ConvertTo-SafeHtml $_.Title)</h3><span class='area'>$(ConvertTo-SafeHtml $_.Area)</span></div>
  <p>$(ConvertTo-SafeHtml $_.Summary)</p>
  $table
</section>
"@
}) -join "`n"

$html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AD health: $(ConvertTo-SafeHtml $domain.DNSRoot) $($now.ToString('yyyy-MM-dd'))</title>
<style>
  body { font: 14px/1.5 "Segoe UI", system-ui, sans-serif; color: #1d2329; background: #f4f5f7; margin: 0; }
  main { max-width: 1000px; margin: 0 auto; padding: 24px 16px 48px; }
  h1 { font-size: 22px; margin: 0 0 4px; } h3 { font-size: 15px; margin: 0; }
  .meta { color: #5b6570; margin: 0 0 20px; }
  .tiles { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 24px; }
  .tile { background: #fff; border-radius: 8px; padding: 12px 16px; border-left: 4px solid; }
  .tile b { display: block; font-size: 26px; } .tile span { color: #5b6570; }
  .check { background: #fff; border-radius: 8px; padding: 14px 16px; margin-bottom: 10px; }
  .head { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .area { margin-left: auto; color: #5b6570; font-size: 12px; }
  .check p { margin: 6px 0 0; }
  .badge { font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 99px; color: #fff; }
  .critical { background: #b42318; border-color: #b42318; } .warning { background: #b54708; border-color: #b54708; }
  .info { background: #175cd3; border-color: #175cd3; } .ok { background: #067647; border-color: #067647; }
  .tile.critical, .tile.warning, .tile.info, .tile.ok { background: #fff; }
  details { margin-top: 8px; } summary { cursor: pointer; color: #5b6570; }
  .table-wrap, details { overflow-x: auto; }
  table { border-collapse: collapse; margin-top: 8px; width: 100%; font-size: 13px; }
  th, td { text-align: left; padding: 5px 8px; border-bottom: 1px solid #e4e7ec; white-space: nowrap; }
  th { background: #f9fafb; }
  @media (max-width: 600px) { .tiles { grid-template-columns: repeat(2, 1fr); } }
</style></head><body><main>
<h1>Active Directory health report</h1>
<p class="meta">Domain <b>$(ConvertTo-SafeHtml $domain.DNSRoot)</b> &middot; run on <b>$env:COMPUTERNAME</b>
($(ConvertTo-SafeHtml $os.Caption)) &middot; up $($uptime.Days)d $($uptime.Hours)h &middot;
generated $($now.ToString('yyyy-MM-dd HH:mm')) &middot; overall: <b>$worst</b></p>
<div class="tiles">$summaryHtml</div>
$checksHtml
</main></body></html>
"@

# .NET resolves relative paths against the process folder, not $PWD, so make it absolute first.
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$path = Join-Path $OutputFolder "AD-Health-$($now.ToString('yyyy-MM-dd')).html"
[System.IO.File]::WriteAllText($path, $html, (New-Object System.Text.UTF8Encoding $false))
Write-Output "Report saved: $path (overall: $worst)"
