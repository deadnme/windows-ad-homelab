<#
.SYNOPSIS
    Turns DC01 into the first domain controller of a brand-new domain.

.DESCRIPTION
    Two steps:
      1. Install the "AD DS" role (the Active Directory software).
      2. "Promote" the server: create a new forest and domain called
         harborpoint.internal, with DNS installed on the same server.

    Why .internal and not .local?
      .local is used by Apple Bonjour / mDNS and causes odd name-lookup
      problems. In 2024 ICANN reserved .internal for private networks, so it
      will never be a real public domain. (Many real companies use a
      subdomain of a domain they own, e.g. ad.harborpoint.com.)

    The server REBOOTS by itself at the end. That's normal.
#>

# LAB ONLY password. DSRM = Directory Services Restore Mode, a special
# "safe mode" login used to repair Active Directory. Store it somewhere safe
# in real life.
$dsrm = ConvertTo-SecureString 'HarborLab!2026' -AsPlainText -Force

# Step 1: install the role and its management tools (ADUC, GPMC, etc.)
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# Step 2: create the forest/domain. -InstallDns makes DC01 the DNS server.
Install-ADDSForest `
    -DomainName 'harborpoint.internal' `
    -DomainNetbiosName 'HARBORPOINT' `
    -InstallDns `
    -SafeModeAdministratorPassword $dsrm `
    -Force
# After the reboot, log in as HARBORPOINT\Administrator.
