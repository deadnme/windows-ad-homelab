<#
.SYNOPSIS
    Joins WS01 (the Windows 11 PC) to the harborpoint.internal domain.
    Run inside WS01 as the local admin (labadmin).

.DESCRIPTION
    Before joining, the PC must be able to FIND the domain. That happens
    through DNS: the PC asks its DNS server (DC01, handed out by DHCP) for
    the domain's "SRV records", which say where the domain controllers are.
    Nine out of ten "domain not found" errors are really DNS problems.

    Joining creates a computer account for WS01 in AD. Because script 04
    ran redircmp, it lands in HarborPoint\Computers\Workstations, where the
    Workstation Security GPO is linked.
#>

# 1. Get a fresh address from DC01's DHCP and check DNS is DC01
ipconfig /renew | Out-Null
Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses

# 2. Can we find a domain controller? (should list DC01)
nltest /dsgetdc:harborpoint.internal

# 3. Join, using a domain account allowed to add computers
$cred = New-Object PSCredential 'HARBORPOINT\Administrator', (ConvertTo-SecureString 'HarborLab!2026' -AsPlainText -Force)   # lab-only
Add-Computer -DomainName harborpoint.internal -Credential $cred -Restart
