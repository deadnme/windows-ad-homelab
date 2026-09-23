<#
.SYNOPSIS
    Sets up DNS and DHCP on DC01. Run after the post-promotion reboot.

.DESCRIPTION
    DNS  = the "phone book": turns names (dc01.harborpoint.internal) into IPs.
    DHCP = hands out IP addresses automatically to workstations.

    What this does:
      - DC01 uses itself for DNS (127.0.0.1)
      - Forwarders: names DC01 doesn't know (google.com) get asked upstream
      - A reverse lookup zone: IP -> name lookups (used by nslookup, tools)
      - A DHCP scope: 10.10.10.100 - 10.10.10.200 for workstations
      - "Authorizes" the DHCP server in AD (an unauthorized one won't hand
        out addresses - a safety feature against rogue DHCP servers)
#>

# --- DNS --------------------------------------------------------------------
Set-DnsClientServerAddress -InterfaceAlias HarborNet -ServerAddresses 127.0.0.1
Set-DnsServerForwarder -IPAddress 1.1.1.1, 8.8.8.8
Add-DnsServerPrimaryZone -NetworkId '10.10.10.0/24' -ReplicationScope Domain
# Register DC01's own PTR (reverse) record now that the zone exists
ipconfig /registerdns | Out-Null

# --- Time -------------------------------------------------------------------
# Kerberos logins FAIL if a PC's clock is more than 5 minutes off the DC's.
# Every domain member syncs time from the DCs; the first DC (the "PDC
# emulator") is the root of that chain, so IT points it at real internet time.
w32tm /config /manualpeerlist:"time.windows.com,0x8 pool.ntp.org,0x8" /syncfromflags:manual /reliable:yes /update | Out-Null
Restart-Service W32Time
w32tm /resync /force | Out-Null

# --- DHCP -------------------------------------------------------------------
Install-WindowsFeature DHCP -IncludeManagementTools

# Security groups the DHCP console expects (DHCP Administrators / Users)
netsh dhcp add securitygroups | Out-Null
Restart-Service DHCPServer

# Authorize this DHCP server in Active Directory
Add-DhcpServerInDC -DnsName 'dc01.harborpoint.internal' -IPAddress 10.10.10.10

# The scope: which addresses to give out, and for how long (8 days = default)
Add-DhcpServerv4Scope -Name 'HarborPoint Workstations' `
    -StartRange 10.10.10.100 -EndRange 10.10.10.200 `
    -SubnetMask 255.255.255.0 -LeaseDuration 8.00:00:00 -State Active

# Scope options: what every client is told besides its IP
Set-DhcpServerv4OptionValue -ScopeId 10.10.10.0 `
    -Router 10.10.10.1 `
    -DnsServer 10.10.10.10 `
    -DnsDomain 'harborpoint.internal'

# Tell Server Manager the post-install DHCP wizard is done (hides the yellow flag)
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2

Get-DhcpServerv4Scope
Get-DnsServerForwarder
