<#
.SYNOPSIS
    Creates a shared folder for each department plus a company-wide Public share.

.DESCRIPTION
    Every shared folder has TWO layers of permissions, and the stricter one wins:
      Share permissions  - checked when you connect over the network (\\DC01\Sales)
      NTFS permissions   - checked on the folder itself, over the network AND locally

    The common practice (and what we do here):
      Share: Authenticated Users = Full Control   (wide open at this layer...)
      NTFS:  the DL_Share_<Dept> group = Modify   (...and control access here)
    That way there's only ONE place to look when access is wrong.

    Access-Based Enumeration (ABE) hides the files and folders INSIDE a share
    that you can't open. It does NOT hide the share names themselves: in my
    lab, Sales staff still see "Accounting" in `net view \\DC01`, they just
    get "Access is denied" when they try to open it.

    In a real company the shares would live on a separate file server, not
    on the domain controller. With only 2 VMs in this lab, DC01 does both.
#>

$base  = 'C:\Shares'
$depts = 'Management','Accounting','Sales','Operations','HR','IT','Public'

foreach ($d in $depts) {
    $path = Join-Path $base $d
    New-Item -Path $path -ItemType Directory -Force | Out-Null

    # NTFS: stop inheriting from C:\Shares, then grant exactly what we want.
    #   (OI)(CI) = applies to this folder, subfolders and files
    #   F = Full control, M = Modify (read, write, delete - but NOT change permissions)
    icacls $path /inheritance:r `
        /grant:r 'BUILTIN\Administrators:(OI)(CI)F' `
        /grant:r 'NT AUTHORITY\SYSTEM:(OI)(CI)F' `
        /grant:r "HARBORPOINT\DL_Share_${d}:(OI)(CI)M" | Out-Null

    # SMB share with Access-Based Enumeration turned on
    New-SmbShare -Name $d -Path $path -FullAccess 'NT AUTHORITY\Authenticated Users' `
        -FolderEnumerationMode AccessBased -Description "$d department share" | Out-Null

    # A starter file so the share isn't empty in screenshots
    Set-Content -Path "$path\README.txt" -Value "Harbor Point $d share. Ask IT (ext. 200) for access."
}

Get-SmbShare -Special $false | Format-Table Name, Path, FolderEnumerationMode -AutoSize
