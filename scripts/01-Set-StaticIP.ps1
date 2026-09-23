<#
.SYNOPSIS
    Gives DC01 a fixed (static) IP address. Run inside DC01 as Administrator.

.DESCRIPTION
    A domain controller must NEVER change its IP address. Every computer in
    the domain finds it by IP (it is their DNS server), so if the address
    moved, nobody could log in. That's why servers get static IPs and
    workstations get addresses from DHCP.

      IP address   10.10.10.10
      Subnet mask  255.255.255.0   (written as /24 below)
      Gateway      10.10.10.1      (VirtualBox's NAT router, the way out to the internet)
      DNS server   127.0.0.1       (itself - it will BE the DNS server after step 02)
#>

# Find the (only) network adapter
$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1

# Remove any address it picked up before, then set the static one
Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute     -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress 10.10.10.10 -PrefixLength 24 -DefaultGateway 10.10.10.1 | Out-Null

# Until AD DS is installed there is no local DNS yet, so use a public one
# temporarily. Promoting to a DC (script 02) points DNS at itself.
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses 1.1.1.1

# Name the adapter something readable
Rename-NetAdapter -Name $nic.Name -NewName 'HarborNet'

# The unattended install already named the server DC01. Double-check it.
if ($env:COMPUTERNAME -ne 'DC01') { Rename-Computer -NewName DC01 -Restart }

Get-NetIPConfiguration -InterfaceAlias HarborNet
