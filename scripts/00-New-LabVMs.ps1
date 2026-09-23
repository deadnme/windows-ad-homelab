<#
.SYNOPSIS
    Builds the Harbor Point lab on the HOST laptop: one private network and two VMs.

.DESCRIPTION
    Run this on your own Windows PC (not inside a VM), in PowerShell.
    It needs VirtualBox 7.x and the two evaluation ISOs from Microsoft:
      - Windows Server 2025 Evaluation  -> $IsoDir\server2025.iso
      - Windows 11 Enterprise Evaluation -> $IsoDir\win11ent.iso

    What it creates:
      HarborNet  a VirtualBox "NAT Network" (10.10.10.0/24). The VMs can reach
                 the internet through the laptop, but nothing on your home
                 network can reach them. VirtualBox's own DHCP is OFF because
                 our domain controller will be the DHCP server.
      DC01       Windows Server 2025 (Desktop Experience) - the domain controller
      WS01       Windows 11 Enterprise - an employee's workstation

    Both VMs install Windows by themselves ("unattended install") and also
    install VirtualBox Guest Additions, which lets the host run commands
    inside them later.

    LAB ONLY: the password below is written in plain text on purpose so the
    lab is easy to rebuild. Never do this with a real password.
#>

$VBox     = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$IsoDir   = "$HOME\LabISOs"
$VmDir    = "$HOME\VirtualBox VMs"
$Password = 'HarborLab!2026'   # lab-only password

# --- 1. The private lab network ------------------------------------------
& $VBox natnetwork add --netname HarborNet --network 10.10.10.0/24 --enable --dhcp off

# --- 2. A helper that builds one VM ---------------------------------------
function New-LabVM($Name, $OsType, $DiskGB) {
    & $VBox createvm --name $Name --ostype $OsType --register
    # 4 GB RAM, 2 CPUs, UEFI firmware, network card plugged into HarborNet
    & $VBox modifyvm $Name --memory 4096 --cpus 2 --vram 128 `
        --graphicscontroller vboxsvga --firmware efi `
        --nic1 natnetwork --nat-network1 HarborNet --audio-enabled off
    # A virtual hard disk plus two empty DVD drives (the installer uses them)
    $disk = "$VmDir\$Name\$Name.vdi"
    & $VBox createmedium disk --filename $disk --size ($DiskGB * 1024)
    & $VBox storagectl $Name --name SATA --add sata --controller IntelAhci --portcount 4
    & $VBox storageattach $Name --storagectl SATA --port 0 --type hdd --medium $disk
    & $VBox storageattach $Name --storagectl SATA --port 1 --type dvddrive --medium emptydrive
    & $VBox storageattach $Name --storagectl SATA --port 2 --type dvddrive --medium emptydrive
}

# --- 3. DC01: Windows Server 2025 -----------------------------------------
New-LabVM DC01 Windows2025_64 60
# Image index 2 = "Standard Evaluation (Desktop Experience)", i.e. with a GUI.
# --user=Administrator sets the built-in Administrator's password.
& $VBox unattended install DC01 --iso="$IsoDir\server2025.iso" `
    --user=Administrator --user-password=$Password --full-user-name=Administrator `
    --hostname=DC01.harborpoint.internal --image-index=2 `
    --install-additions --locale=en_US --country=US `
    --start-vm=headless

# --- 4. WS01: Windows 11 Enterprise ----------------------------------------
New-LabVM WS01 Windows11_64 64
# Windows 11 wants a TPM 2.0 chip and Secure Boot, so give it both.
& $VBox modifyvm WS01 --tpm-type 2.0
& $VBox modifynvram WS01 inituefivarstore
& $VBox modifynvram WS01 enrollmssignatures
& $VBox modifynvram WS01 enrollorclpk
# A local admin account (labadmin) is used until the PC joins the domain.
& $VBox unattended install WS01 --iso="$IsoDir\win11ent.iso" `
    --user=labadmin --user-password=$Password --full-user-name="Lab Admin" `
    --hostname=WS01.harborpoint.internal --image-index=1 `
    --install-additions --locale=en_US --country=US `
    --start-vm=headless

Write-Host "Both VMs are installing. This takes 20-40 minutes. Watch with: VirtualBox Manager -> Show"
