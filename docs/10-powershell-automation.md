# 10 · PowerShell automation

> **Goal:** turn the repetitive admin jobs into scripts that are safe to run: bulk user creation, onboarding, offboarding and a stale-account report.

## Why a company does this

Clicking through ADUC is fine once. Doing it for 15 new hires, or doing offboarding the *same way every time* at 5pm on a Friday, is where mistakes happen. A script does the same steps in the same order every time, and it doubles as documentation of the process.

All four scripts are in [`scripts/automation/`](../scripts/automation/) and were run against the lab. The output below is real.

## Safety features every script uses

| Feature | What it does | Why |
|---|---|---|
| `[CmdletBinding(SupportsShouldProcess)]` | Adds `-WhatIf` and `-Confirm` | Preview changes before making them |
| Skip-if-exists checks | Won't create duplicates | Safe to run twice |
| `ValidateSet` on Department | Only accepts real departments | A typo like "Sale" fails immediately instead of creating a broken user |
| Logs to `C:\ITLogs` | Keeps a record | Audit trail, and an undo path |

---

## 1. `New-BulkUsers.ps1`: create users from a CSV

Input: [`new-hires-example.csv`](../scripts/automation/new-hires-example.csv)
```csv
FirstName,LastName,Department,Title
Noah,Fischer,Accounting,Junior Accountant
Chloe,Bennett,Operations,Office Assistant
```

**Always preview first with `-WhatIf`:**
```
PS> .\New-BulkUsers.ps1 -CsvPath .\new-hires-example.csv -WhatIf
What if: Performing the operation "Create user in Accounting" on target "noah.fischer".
What if: Performing the operation "Create user in Operations" on target "chloe.bennett".
```
**Then for real:**
```
PS> .\New-BulkUsers.ps1 -CsvPath .\new-hires-example.csv
Created noah.fischer (Accounting)
Created chloe.bennett (Operations)
```
**Running it again is safe:**
```
PS> .\New-BulkUsers.ps1 -CsvPath .\new-hires-example.csv
WARNING: noah.fischer already exists - skipped
WARNING: chloe.bennett already exists - skipped
```
This same script created the original 20 staff from `users.csv` (script 04 calls it).

The core of it:
```powershell
foreach ($u in Import-Csv $CsvPath) {
    $sam = "$($u.FirstName).$($u.LastName)".ToLower() -replace '[^a-z0-9.]', ''
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'") { Write-Warning "$sam already exists - skipped"; continue }
    if ($PSCmdlet.ShouldProcess($sam, "Create user in $($u.Department)")) {
        New-ADUser -Name "$($u.FirstName) $($u.LastName)" -SamAccountName $sam -Path "OU=$($u.Department),$root" ...
        Add-ADGroupMember "GG_$($u.Department)" -Members $sam
    }
}
```
> 🎓 `-replace '[^a-z0-9.]', ''` strips anything that isn't a letter, number or dot, so "O'Brien" becomes `obrien` instead of breaking the logon name.

---

## 2. `Invoke-Onboarding.ps1`: one new starter, done properly

Differences from the bulk script:
- Generates a **random 16-character password** that always meets complexity (at least one upper, lower, number and symbol).
- Sets the **manager** field (it shows in Outlook/Teams org charts in a real company).
- Prints a **summary to paste into the ticket**.

```
PS> .\Invoke-Onboarding.ps1 -FirstName Liam -LastName Ortiz -Department Sales -Title 'Sales Representative' -Manager rachel.kim

Username      : HARBORPOINT\liam.ortiz
Email_UPN     : liam.ortiz@harborpoint.internal
Department    : Sales
Groups        : Domain Users, GG_Sales
TempPassword  : Ze4%c$Ny3bKS!UJK
MustChangePwd : True
```
Wrong department name? It fails before touching AD:
```
PS> .\Invoke-Onboarding.ps1 -FirstName Test -LastName User -Department Sale -Title x
Cannot validate argument on parameter 'Department'. The argument "Sale" does not belong to the set
"Management,Accounting,Sales,Operations,HR,IT" specified by the ValidateSet attribute. Supply an
argument that is in the set and then try the command again.
```

---

## 3. `Invoke-Offboarding.ps1`: leaver process

```
PS> .\Invoke-Offboarding.ps1 -SamAccountName diego.santos -Ticket HD-1004

Name              : Diego Santos
Enabled           : False
Description       : Disabled 2026-09-23 - HD-1004
DistinguishedName : CN=Diego Santos,OU=Disabled Users,OU=HarborPoint,DC=harborpoint,DC=internal
Groups left       : 0
Group list saved to C:\ITLogs\Offboarding
```
The steps, and why each one is there, are in [ticket HD-1004](09-helpdesk-tickets.md#hd-1004--leaver-diego-santos-last-day-today).

---

## 4. `Get-StaleAccounts.ps1`: who hasn't logged in for 90 days?

Old, unused accounts are a favourite target for attackers because nobody notices when they're used. Many companies run this report monthly.

```
PS> .\Get-StaleAccounts.ps1 -Days 90
(no results - every account in the lab is minutes old)
```
With `-Days 0` as a demo (so every enabled account counts), exported to CSV:
```
PS> .\Get-StaleAccounts.ps1 -Days 0 -CsvPath C:\ITLogs\stale.csv
Saved 25 rows to C:\ITLogs\stale.csv

Name              SamAccountName    Department LastLogon            WhenCreated
----              --------------    ---------- ---------            -----------
Margaret Holloway margaret.holloway Management Never                9/23/2026 3:15:31 AM
Rachel Kim        rachel.kim        Sales      9/23/2026 3:40:54 AM 9/23/2026 3:15:33 AM
Liam Ortiz        liam.ortiz        Sales      Never                9/23/2026 3:53:18 AM
...
```
Notice Diego Santos isn't listed: the report only checks **enabled** accounts, and he was disabled by the offboarding script.

> 🎓 `LastLogonDate` comes from the `lastLogonTimestamp` attribute, which AD only updates every **9–14 days** to cut down on replication traffic. It's accurate enough for a "90 days" report, but don't use it to answer "did they log in this morning?". For that, check the DC's security log (event 4624).

---

## Ideas to extend this (not built yet)

- Email the stale report to IT monthly (a scheduled task + `Send-MailMessage` or Graph API).
- Offboarding step that also hides the user from the address book and converts the mailbox (needs Exchange/M365).
- A `Restore-OffboardedUser.ps1` that reads the saved CSV and puts the groups back.

## Interview questions

- **"Have you used PowerShell for AD?"** Yes: I wrote bulk-create, onboarding, offboarding and stale-account scripts for my lab using the ActiveDirectory module (`New-ADUser`, `Add-ADGroupMember`, `Search-ADAccount`, `Get-ADUser -Filter`), with `-WhatIf` support and CSV logging.
- **"What does `-WhatIf` do?"** Shows what a command *would* change without changing anything.
- **"How would you find all locked-out users?"** `Search-ADAccount -LockedOut`
- **"How would you find disabled accounts?"** `Search-ADAccount -AccountDisabled -UsersOnly`

⬅️ [09 · Help desk tickets](09-helpdesk-tickets.md) | ➡️ [11 · Troubleshooting and lessons](11-troubleshooting-and-lessons.md)
