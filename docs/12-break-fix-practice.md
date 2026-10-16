# 12 · Break-fix practice

> Someone else broke seven things in the working lab without telling me how. I only had the ticket, the same as on a real help desk. This page is **my own troubleshooting notes**: what I checked, what I found, and how I fixed it.

**Rules I followed**
- Start from the symptom, not a guess. Write down every command I ran and what it showed.
- Change one thing at a time, then re-test.
- A snapshot called `before-breakfix` exists on both VMs if I get completely stuck. Rolling back counts as giving up on that ticket.

**Logins:** DC01 `HARBORPOINT\Administrator` · WS01 as Rachel: `rachel.kim` (all lab-only passwords)

---

## BF-1 · "Websites work, but nothing company-related does"
**Reported by:** Rachel Kim (Sales), on WS01
> "I can browse the internet fine, but my shared drives won't open and the IT tool you told me to run (`gpupdate`) gave an error."

- **What I checked:**
- **What I found:**
- **Fix:**
- **How I verified it:**
- **What I'd tell the user:**

---

## BF-2 · "My P: and S: drives are gone"
**Reported by:** Rachel Kim, and then two other departments
> "I signed out and back in like you said. Still no P: or S: drive. My colleagues in other departments don't have them either."

- **What I checked:**
- **What I found:**
- **Fix:**
- **How I verified it:**
- **What I'd tell the user:**

---

## BF-3 · "Access denied on the Accounting folder"
**Reported by:** Priya Patel (Accounting)
> "Yesterday I could open the Accounting share. Today it says Access is denied."
*(I can't sign in as Priya, so I investigated from the server side.)*

- **What I checked:**
- **What I found:**
- **Fix:**
- **How I verified it:**
- **What I'd tell the user:**

---

## BF-4 · "I can open files on P: but I can't save anything"
**Reported by:** Rachel Kim
> "Opening files from the Public drive works. Saving a new file there says access denied."

- **What I checked:**
- **What I found:**
- **Fix:**
- **How I verified it:**
- **What I'd tell the user:**

---

## BF-5 · "Your account has expired"
**Reported by:** Hannah Lee (Sales), by phone
> "When I sign in it says: *Your account has expired. Please contact your system administrator.* I haven't left the company!"

- **What I checked:**
- **What I found:**
- **Fix:**
- **How I verified it:**
- **What I'd tell the user:**

---

## BF-6 · "The new laptop has no network, and its IP starts with 169.254"
**Reported by:** Operations
> "We plugged in a new laptop and it says No internet. The IP address starts with 169.254."
*(To reproduce it on WS01: `ipconfig /release` then `ipconfig /renew`. WS01 loses its network until this is fixed.)*

- **What I checked:**
- **What I found:**
- **Fix:**
- **How I verified it:**
- **What I'd tell the user:**

---

## BF-7 · "We keep getting locked out after the password change"
**Reported by:** Sales (Marcus Johnson, Emily Carter, Liam Ortiz)
> "IT made all of us change our passwords this morning. We all did, and we're typing the new one right. Since then we keep getting locked out. The help desk unlocks us, and ten minutes later we're locked out again."
*(Lab-only: their new password is `Spring-Harbor#2026`.)*

- **What I checked:**
- **What I found:**
- **Fix:**
- **How I verified it:**
- **What I'd tell the user:**

---

## What I learned

-
