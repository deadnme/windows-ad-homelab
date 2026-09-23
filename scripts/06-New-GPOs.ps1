<#
.SYNOPSIS
    Creates Harbor Point's Group Policy Objects (GPOs) and links them to OUs.

.DESCRIPTION
    A GPO is a bundle of settings. You LINK it to a site, the domain or an OU,
    and every user/computer in there applies it (at startup, at logon, and
    every ~90 minutes in the background).

      GPO                         Linked to                What it does
      --------------------------  -----------------------  ------------------------------
      Default Domain Policy       the domain               Password + lockout rules
      HP - Workstation Security   Workstations OU          Lock screen after 10 min, logon banner
      HP - Staff Desktop          each dept OU except IT   Company wallpaper, block regedit
      HP - Drive Mappings         Users OU                 P: = Public, S: = your dept share
      HP - Sales USB Block        Sales OU                 No USB sticks (client data risk)

    Two things the GroupPolicy PowerShell module can't do directly, so this
    script does them by hand (the GPMC GUI does the same thing behind the scenes):
      1. Password policy lives in a file called GptTmpl.inf inside SYSVOL.
      2. Drive maps are "Group Policy Preferences", stored in Drives.xml.
    After editing files by hand we must raise the GPO's version number,
    otherwise clients think nothing changed and skip it.
#>

Import-Module ActiveDirectory, GroupPolicy
$domain  = (Get-ADDomain).DistinguishedName
$root    = "OU=HarborPoint,$domain"
$sysvol  = 'C:\Windows\SYSVOL\domain\Policies'

# Raise a GPO's version in BOTH places clients check: AD and GPT.INI.
# Low 16 bits = computer-settings version, high 16 bits = user-settings version.
function Step-GpoVersion([Guid]$Id, [int]$Add) {
    $dn  = "CN={$Id},CN=Policies,CN=System,$domain"
    $ver = (Get-ADObject $dn -Properties versionNumber).versionNumber + $Add
    Set-ADObject $dn -Replace @{ versionNumber = $ver }
    $ini = "$sysvol\{$Id}\GPT.INI"
    (Get-Content $ini) -replace '^Version=\d+', "Version=$ver" | Set-Content $ini -Encoding ASCII
}

# --- 1. Password & lockout policy (Default Domain Policy) --------------------
# Account policies ONLY work when set at the domain level. Put them in a GPO
# linked to an OU and they're silently ignored for domain accounts.
$ddp = Get-GPO -Name 'Default Domain Policy'
$inf = "$sysvol\{$($ddp.Id)}\MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf"
$policy = [ordered]@{
    MinimumPasswordLength = 12   # characters
    PasswordComplexity    = 1    # needs 3 of: upper, lower, number, symbol
    MaximumPasswordAge    = 90   # days before a forced change
    PasswordHistorySize   = 24   # can't reuse the last 24 passwords
    LockoutBadCount       = 5    # lock after 5 wrong passwords...
    ResetLockoutCount     = 15   # ...within 15 minutes
    LockoutDuration       = 15   # stays locked 15 minutes (or until help desk unlocks)
}
$text = Get-Content $inf -Raw -Encoding Unicode
foreach ($k in $policy.Keys) {
    if ($text -match "(?m)^$k = ") { $text = $text -replace "(?m)^$k = [^\r\n]*", "$k = $($policy[$k])" }
    else                           { $text = $text -replace '\[System Access\]', "[System Access]`r`n$k = $($policy[$k])" }
}
Set-Content $inf $text -Encoding Unicode -NoNewline
Step-GpoVersion $ddp.Id 1

# --- 2. Workstation Security (computer settings) ------------------------------
$gpo = New-GPO -Name 'HP - Workstation Security' -Comment 'Screen lock and logon banner for all workstations'
$sys = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System'
Set-GPRegistryValue -Guid $gpo.Id -Key $sys -ValueName InactivityTimeoutSecs -Type DWord -Value 600 | Out-Null
Set-GPRegistryValue -Guid $gpo.Id -Key $sys -ValueName LegalNoticeCaption -Type String -Value 'Harbor Point Accounting - Authorized Use Only' | Out-Null
Set-GPRegistryValue -Guid $gpo.Id -Key $sys -ValueName LegalNoticeText -Type String `
    -Value 'This computer is the property of Harbor Point Accounting. Activity may be monitored. Need help? Call IT on ext. 200.' | Out-Null
# "Interactive logon: Don't display last signed-in" - don't show usernames to passers-by
Set-GPRegistryValue -Guid $gpo.Id -Key $sys -ValueName DontDisplayLastUserName -Type DWord -Value 1 | Out-Null
New-GPLink -Guid $gpo.Id -Target "OU=Workstations,OU=Computers,$root" | Out-Null

# --- 3. Staff Desktop (user settings) -----------------------------------------
# Wallpaper lives in NETLOGON: every user can read it, only admins can change it.
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap 1920, 1080
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(14, 55, 84))
$g.DrawString('Harbor Point Accounting', (New-Object System.Drawing.Font('Segoe UI', 64, [System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::White, 120, 760)
$g.DrawString('IT Help Desk: ext. 200  |  helpdesk@harborpoint.internal', (New-Object System.Drawing.Font('Segoe UI', 28)), [System.Drawing.Brushes]::LightGray, 128, 880)
$bmp.Save('C:\Windows\SYSVOL\domain\scripts\wallpaper.jpg', [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $bmp.Dispose()

$gpo = New-GPO -Name 'HP - Staff Desktop' -Comment 'Company wallpaper and no registry editor for non-IT staff'
$usys = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System'
Set-GPRegistryValue -Guid $gpo.Id -Key $usys -ValueName Wallpaper -Type String -Value '\\harborpoint.internal\NETLOGON\wallpaper.jpg' | Out-Null
Set-GPRegistryValue -Guid $gpo.Id -Key $usys -ValueName WallpaperStyle -Type String -Value '4' | Out-Null   # 4 = Fill
Set-GPRegistryValue -Guid $gpo.Id -Key $usys -ValueName DisableRegistryTools -Type DWord -Value 1 | Out-Null
# IT staff need regedit, so link to every department OU except IT.
'Management','Accounting','Sales','Operations','HR' | ForEach-Object {
    New-GPLink -Guid $gpo.Id -Target "OU=$_,OU=Users,$root" | Out-Null
}

# --- 4. Drive Mappings (Group Policy Preferences) -----------------------------
# P: for everyone. S: only if you're in that department's GG_ group -
# that "only if" is called Item-Level Targeting.
$gpo = New-GPO -Name 'HP - Drive Mappings' -Comment 'P: Public for all, S: department share by group'
function DriveXml($letter, $share, $filterGroup) {
    $filter = ''
    if ($filterGroup) {
        $sid = (Get-ADGroup $filterGroup).SID.Value
        $filter = "<Filters><FilterGroup bool=`"AND`" not=`"0`" name=`"HARBORPOINT\$filterGroup`" sid=`"$sid`" userContext=`"1`" primaryGroup=`"0`" localGroup=`"0`"/></Filters>"
    }
    $uid = [Guid]::NewGuid().ToString('B').ToUpper()
    @"
  <Drive clsid="{935D1B74-9CB8-4e3c-9914-7DD559B7A417}" name="${letter}:" status="${letter}:" image="2" changed="$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" uid="$uid" bypassErrors="1">
    <Properties action="U" thisDrive="NOCHANGE" allDrives="NOCHANGE" userName="" path="\\DC01\$share" label="$share" persistent="1" useLetter="1" letter="$letter"/>$filter
  </Drive>
"@
}
$drives = (DriveXml P Public $null)
foreach ($d in 'Management','Accounting','Sales','Operations','HR','IT') { $drives += (DriveXml S $d "GG_$d") }
$xml = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<Drives clsid=`"{8FDDCC1A-0C3C-43cd-A6B4-71A6DF20DA8C}`">`r`n$drives</Drives>"
$dir = "$sysvol\{$($gpo.Id)}\User\Preferences\Drives"
New-Item $dir -ItemType Directory -Force | Out-Null
Set-Content "$dir\Drives.xml" $xml -Encoding UTF8
# Tell clients this GPO contains Drive Maps (the "client-side extension" GUIDs)
Set-ADObject "CN={$($gpo.Id)},CN=Policies,CN=System,$domain" -Replace @{
    gPCUserExtensionNames = '[{00000000-0000-0000-0000-000000000000}{2EA1A81B-48E5-45E9-8BB7-A6E3AC170006}][{5794DAFD-BE60-433F-88A2-1A31939AC01F}{2EA1A81B-48E5-45E9-8BB7-A6E3AC170006}]'
}
Step-GpoVersion $gpo.Id 65536   # +1 to the USER version
New-GPLink -Guid $gpo.Id -Target "OU=Users,$root" | Out-Null

# --- 5. Sales USB Block -------------------------------------------------------
$gpo = New-GPO -Name 'HP - Sales USB Block' -Comment 'Sales handle client financials: no removable storage'
Set-GPRegistryValue -Guid $gpo.Id -Key 'HKCU\Software\Policies\Microsoft\Windows\RemovableStorageDevices' `
    -ValueName Deny_All -Type DWord -Value 1 | Out-Null
New-GPLink -Guid $gpo.Id -Target "OU=Sales,OU=Users,$root" | Out-Null

gpupdate /force | Out-Null
Get-ADDefaultDomainPasswordPolicy
Get-GPO -All | Sort-Object DisplayName | Format-Table DisplayName, GpoStatus, ModificationTime -AutoSize
