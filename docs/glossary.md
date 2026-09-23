# Glossary

Quick definitions for every term used in this lab, alphabetical.

| Term | Meaning |
|---|---|
| **ABE (Access-Based Enumeration)** | Hides the files and folders *inside* a share that you don't have permission to open. It does **not** hide the share names in `net view`. |
| **Account lockout** | After too many wrong passwords (5 here), AD locks the account for a while to slow down password guessing. |
| **AD DS** | Active Directory Domain Services, the Windows Server role that makes a server a domain controller. |
| **ADUC** | "Active Directory Users and Computers" (`dsa.msc`), the classic GUI for managing users, groups and OUs. |
| **AdminSDHolder / SDProp** | A background process (every 60 min) that resets the permissions on members of admin groups like Domain Admins, so delegated rights can't reach them. New admins are exposed until it runs. |
| **AGDLP** | **A**ccounts go into **G**lobal groups, which go into **D**omain **L**ocal groups, which get **P**ermissions. Keeps permissions tidy. |
| **Authentication** | Proving who you are (password). |
| **Authorization** | What you're allowed to do once you're known (permissions). |
| **DC (Domain Controller)** | A server running AD DS. It holds the directory and checks logins. |
| **DHCP** | Protocol that hands out IP addresses and settings (gateway, DNS) automatically. |
| **DHCP scope** | The range of addresses a DHCP server may give out (10.10.10.100-200 here). |
| **DHCP lease** | A temporary loan of an IP address to a device (8 days here). |
| **Distinguished Name (DN)** | An object's full "path" in AD, e.g. `CN=Priya Patel,OU=Accounting,OU=Users,OU=HarborPoint,DC=harborpoint,DC=internal`. |
| **DNS** | Translates names to IPs. AD clients use it to find domain controllers. |
| **DNS forwarder** | Where the DC sends lookups for names it doesn't know (e.g. google.com). |
| **DFSR** | DFS Replication, the service that builds and replicates SYSVOL between DCs. If it fails, `SysvolReady` stays 0 and the DC doesn't advertise itself. |
| **Domain** | A security boundary of users/computers sharing one AD database. |
| **Event 4740** | Security log event on a DC: "A user account was locked out". It includes the computer the bad passwords came from. |
| **Domain Admins** | The all-powerful group for the domain. Keep it as small as possible. |
| **Domain Local group** | Group scope meant for granting permissions to resources in this domain. |
| **DSRM** | Directory Services Restore Mode, a special safe-mode login for repairing AD. Has its own password. |
| **Forest** | The top container holding one or more domains that trust each other. |
| **FQDN** | Fully Qualified Domain Name, e.g. `dc01.harborpoint.internal`. |
| **Global group** | Group scope meant for collecting users (e.g. everyone in Sales). |
| **GPMC** | Group Policy Management Console (`gpmc.msc`). |
| **GPO** | Group Policy Object, a set of settings linked to a site, domain or OU. |
| **GPP (Group Policy Preferences)** | The newer, more flexible half of Group Policy: drive maps, printers, shortcuts, with item-level targeting. |
| **gpresult** | Command that shows which GPOs applied to a user/PC (`gpresult /r`). |
| **gpupdate** | Command that fetches and applies GPOs now instead of waiting (`gpupdate /force`). |
| **Item-Level Targeting** | A GPP feature: apply a setting only if a condition is true (e.g. "user is in GG_Sales"). |
| **Kerberos** | The ticket-based login protocol AD uses. Very sensitive to clock differences (>5 min = logins fail). |
| **Least privilege** | Give people only the access they need to do their job, nothing more. |
| **NAT Network** | VirtualBox network type: VMs share a private network and reach the internet through the host, but the home network can't reach them. |
| **NetBIOS name** | The short, old-style domain name: `HARBORPOINT` (used in `HARBORPOINT\priya.patel`). |
| **NTFS permissions** | Permissions stored on the folder/file itself. Apply locally and over the network. |
| **OU** | Organizational Unit, a container for organising objects and linking GPOs. |
| **PDC Emulator** | One of the 5 FSMO roles. The domain's time source; it also handles password changes and account lockouts first. |
| **Promote** | Turning a server into a domain controller. |
| **PTR record** | A reverse DNS record: IP → name. Lives in a reverse lookup zone. |
| **RSAT** | Remote Server Administration Tools: ADUC, GPMC, etc. installed on a workstation. |
| **SamAccountName** | The logon name, e.g. `priya.patel`. |
| **Share permissions** | Permissions on the network share. Apply only when connecting over the network. |
| **SID** | Security Identifier, the unique ID behind every user/group. Names can change; SIDs don't. |
| **SRV record** | A DNS record that says which server provides a service. AD's SRV records tell PCs where the DCs are. |
| **SYSVOL** | Folder shared by every DC that holds GPO files and logon scripts. |
| **UAC** | User Account Control. Admins run with a limited token until they approve elevation ("Run as administrator"). |
| **UPN** | User Principal Name, the email-style logon: `priya.patel@harborpoint.internal`. |
