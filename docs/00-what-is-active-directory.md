# 00 · What is Active Directory? (read this first)

> **Goal of this page:** understand the handful of ideas that the rest of the lab is built on. No clicking yet.

## The problem AD solves

Imagine Harbor Point Accounting with 20 staff and 20 PCs, and **no** Active Directory:

- Every PC has its own local accounts. If Priya uses three different PCs, she needs three accounts and three passwords.
- When someone leaves, IT has to walk to every PC and delete their account. Miss one and they can still log in.
- Want a 10-minute screen lock on every PC? That's 20 PCs to click through by hand.
- File shares? Each PC keeps its own list of who's allowed in.

**Active Directory (AD)** fixes this by keeping **one central database** of users, computers and groups, plus **one central place** to push settings to every PC.

## The key words

| Term | Plain-English meaning | In this lab |
|---|---|---|
| **Domain** | A group of users and computers managed together, sharing one AD database | `harborpoint.internal` |
| **Domain Controller (DC)** | The server that holds the AD database and checks passwords when people log in | `DC01` |
| **Forest** | The top-level container for one or more domains. First domain = new forest | one forest, one domain |
| **Object** | Anything stored in AD: a user, a computer, a group, a printer | 20 users, 1 PC, 14 groups |
| **OU (Organizational Unit)** | A folder in AD for organising objects and **targeting Group Policy** | `HarborPoint\Users\Sales` |
| **Security group** | A list of users you grant permissions to all at once | `GG_Sales` |
| **GPO (Group Policy Object)** | A bundle of settings pushed to users/computers in an OU | screen lock, drive maps |
| **DNS** | The "phone book" that turns names into IP addresses. **AD cannot work without it.** | runs on DC01 |
| **DHCP** | Automatically hands out IP addresses to PCs | runs on DC01 |
| **SYSVOL / NETLOGON** | Shared folders on every DC that hold GPO files and logon scripts | `\\harborpoint.internal\SYSVOL` |

## How a login actually works (simplified)

```
 Priya types her password on WS01
          │
          ▼
 WS01 asks DNS: "where is a domain controller for harborpoint.internal?"
          │   (DNS answers: DC01 at 10.10.10.10)
          ▼
 WS01 sends the login to DC01  ──►  DC01 checks the password (Kerberos)
          │
          ▼
 DC01: "OK, she's Priya, member of GG_Accounting, Domain Users"
          │
          ▼
 WS01 downloads the GPOs that apply to her and to itself
 (wallpaper, drive maps, screen lock) and shows her desktop
```

Two lessons hide in that diagram:
1. **If DNS is wrong, nothing works.** That's why the first question in any AD troubleshooting is "what DNS server is this PC using?" It must be the DC, not the router or 8.8.8.8.
2. **Group membership decides what you get.** Permissions and GPO targeting all follow groups, so managing groups is managing access.

## The lab at a glance

```
                        Internet
                           │
                 ┌─────────┴─────────┐
                 │  VirtualBox NAT   │  10.10.10.1 (gateway)
                 │  "HarborNet"      │  isolated from my home network
                 └───┬───────────┬───┘
                     │           │
          ┌──────────┴───┐   ┌───┴──────────────┐
          │ DC01         │   │ WS01             │
          │ 10.10.10.10  │   │ 10.10.10.100+    │
          │ Server 2025  │   │ Windows 11 Ent.  │
          │ AD DS, DNS,  │   │ domain-joined    │
          │ DHCP, Files  │   │ staff PC         │
          └──────────────┘   └──────────────────┘
```

## Interview questions this page prepares you for

- **"What is Active Directory?"** A directory service from Microsoft. It centrally stores users, computers and groups, handles authentication (checking who you are) and authorization (what you may access) across a Windows network, and lets admins push settings with Group Policy.
- **"What's the difference between a domain and a domain controller?"** The domain is the logical group (`harborpoint.internal`); the DC is the actual server that stores and serves it.
- **"Why does AD need DNS?"** Clients use DNS SRV records to find domain controllers. Without correct DNS, a PC can't find a DC, so it can't join the domain or log anyone in.
- **"What's the difference between an OU and a group?"** OUs *organise* objects and are where GPOs are linked. Groups are used to *grant permissions*. A user lives in exactly one OU but can be in many groups.

➡️ Next: [01 · Host and VirtualBox setup](01-host-and-virtualbox-setup.md)
