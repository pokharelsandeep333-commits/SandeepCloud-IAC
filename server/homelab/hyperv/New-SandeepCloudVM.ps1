#Requires -RunAsAdministrator
#Requires -Modules Hyper-V
<#
.SYNOPSIS
Creates a server VM on the homelab laptop (Hyper-V), from the same cloud-init file the
clouds get.

.DESCRIPTION
The homelab is SandeepCloud's temporary home between AWS and the next cloud provider.
This does what Terraform and the cloud would do there:

  1. downloads the Ubuntu 24.04 cloud image (pinned, hash-checked);
  2. converts it to VHDX with qemu-img in WSL and grows it to -DiskGB;
  3. renders server/provision/cloud-init.yaml.tftpl at -RepoRef into a NoCloud seed
     disk (FAT, label CIDATA);
  4. creates a Generation 2 VM on the Default Switch (NAT: outbound only, nothing from
     the internet can reach it) and starts it.

cloud-init then runs bootstrap.sh inside the VM, exactly as on a cloud. No secrets go
in: the keys come in later, by hand, through restore.sh and tunnel-up.sh.

Run it on the laptop in an admin PowerShell. Needs qemu-img in the WSL distro once:
  wsl -d Ubuntu-24.04 -- sudo apt-get install -y qemu-utils

.EXAMPLE
.\New-SandeepCloudVM.ps1 -RepoRef 0123...cdef -SshPublicKey (Get-Content .\id_ed25519.pub)
#>
[CmdletBinding()]
param(
    # The commit the VM clones and runs bootstrap.sh from (full SHA, so a rebuild is repeatable)
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$RepoRef,

    # Public key for user ubuntu, used to SSH in before Tailscale is up (through the laptop)
    [Parameter(Mandatory)]
    [ValidatePattern('^(ssh-ed25519|ecdsa-sha2-nistp256) [A-Za-z0-9+/]+=* ?[A-Za-z0-9._@-]*$')]
    [string]$SshPublicKey,

    [ValidateSet('sandeepcloud', 'adblocker')]
    [string]$Server = 'sandeepcloud',

    [ValidateRange(1, 8)]
    [int]$MemoryGB = 2,

    [ValidateRange(1, 4)]
    [int]$ProcessorCount = 2,

    [ValidateRange(30, 500)]
    [int]$DiskGB = 60,

    # Outside OneDrive: a VM disk must not sync
    [string]$VmRoot = 'C:\homelab\vms',

    [string]$SwitchName = 'Default Switch',

    [string]$WslDistro = 'Ubuntu-24.04'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Ubuntu 24.04 cloud image. The release's SHA256SUMS was checked against Canonical's
# cloud image signing key D2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81 on 2026-10-27.
# cloud-init upgrades every package on first boot, so an older image only costs time.
$ImageUrl = 'https://cloud-images.ubuntu.com/releases/noble/release-20261017/ubuntu-24.04-server-cloudimg-amd64.img'
$ImageSha256 = '04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94'
$RepoRaw = 'https://raw.githubusercontent.com/pokharelsandeep333-commits/SandeepCloud-IAC'

function Write-Step([string]$Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }

# Text files for cloud-init: UTF-8 without a BOM, LF line endings
function Write-LfFile([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
}

# --- Checks -----------------------------------------------------------------------------
Write-Step 'Checks'
if (Get-VM -Name $Server -ErrorAction SilentlyContinue) {
    throw "A VM named '$Server' already exists. Remove it first (Remove-VM, then delete $VmRoot\$Server)."
}
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    throw "No Hyper-V switch named '$SwitchName'."
}
$env:WSL_UTF8 = '1'
$null = wsl.exe -d $WslDistro --exec sh -c 'command -v qemu-img'
if ($LASTEXITCODE -ne 0) {
    throw "qemu-img isn't installed in WSL ($WslDistro). Run once: wsl -d $WslDistro -- sudo apt-get install -y qemu-utils"
}
$vmDir = Join-Path $VmRoot $Server
$imageDir = Join-Path $VmRoot 'images'
New-Item -ItemType Directory -Force -Path $vmDir, $imageDir | Out-Null

# --- Image: download once, check the hash every time -----------------------------------
Write-Step 'Ubuntu cloud image'
$image = Join-Path $imageDir (Split-Path $ImageUrl -Leaf)
if (-not (Test-Path $image)) {
    curl.exe -fL --retry 3 --progress-bar -o "$image.part" $ImageUrl
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $ImageUrl" }
    Move-Item -Force "$image.part" $image
}
$got = (Get-FileHash -Algorithm SHA256 $image).Hash.ToLowerInvariant()
if ($got -ne $ImageSha256) {
    Remove-Item -Force $image
    throw "SHA-256 mismatch for $image (got $got, expected $ImageSha256). Deleted it; run again."
}
Write-Host "OK: $image"

# --- OS disk: qcow2 -> dynamic VHDX, then grown (cloud-init grows the root partition) ----
Write-Step "OS disk ($DiskGB GB)"
$osDisk = Join-Path $vmDir "$Server.vhdx"
$wslImage = (wsl.exe -d $WslDistro --exec wslpath -u $image).Trim()
$wslDisk = (wsl.exe -d $WslDistro --exec wslpath -u $osDisk).Trim()
wsl.exe -d $WslDistro --exec qemu-img convert -f qcow2 -O vhdx -o subformat=dynamic $wslImage $wslDisk
if ($LASTEXITCODE -ne 0) { throw 'qemu-img convert failed' }
Resize-VHD -Path $osDisk -SizeBytes ([int64]$DiskGB * 1GB)

# --- Seed disk: cloud-init's NoCloud data source reads a FAT volume labelled CIDATA ------
Write-Step 'cloud-init seed'
$templateUrl = "$RepoRaw/$RepoRef/server/provision/cloud-init.yaml.tftpl"
$userData = (Invoke-WebRequest -UseBasicParsing -Uri $templateUrl).Content
if ($userData -is [byte[]]) { $userData = [Text.Encoding]::UTF8.GetString($userData) }
# The same three variables Terraform's templatefile() fills in
$userData = $userData.Replace('${host}', $Server).Replace('${ssh_public_key}', $SshPublicKey).Replace('${repo_ref}', $RepoRef)
if ($userData -match '\$\{') { throw "The template at $RepoRef has a variable this script doesn't fill in." }
if (-not $userData.StartsWith('#cloud-config')) { throw "Unexpected template content from $templateUrl" }
$metaData = "instance-id: $Server-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))`nlocal-hostname: $Server`n"

$seedDisk = Join-Path $vmDir "$Server-seed.vhdx"
New-VHD -Path $seedDisk -SizeBytes 64MB -Dynamic | Out-Null
$disk = Mount-VHD -Path $seedDisk -Passthru | Get-Disk
try {
    $disk | Initialize-Disk -PartitionStyle MBR
    $volume = $disk | New-Partition -UseMaximumSize -AssignDriveLetter |
        Format-Volume -FileSystem FAT32 -NewFileSystemLabel CIDATA -Confirm:$false
    $root = "$($volume.DriveLetter):\"
    Write-LfFile (Join-Path $root 'user-data') $userData
    Write-LfFile (Join-Path $root 'meta-data') $metaData
}
finally {
    Dismount-VHD -Path $seedDisk
}

# --- VM ---------------------------------------------------------------------------------
Write-Step "VM $Server ($MemoryGB GB, $ProcessorCount vCPU)"
$vm = New-VM -Name $Server -Generation 2 -MemoryStartupBytes ([int64]$MemoryGB * 1GB) `
    -VHDPath $osDisk -SwitchName $SwitchName -Path $VmRoot
# A server: fixed memory, no checkpoints, starts with the laptop (nobody needs to log in)
Set-VM -VM $vm -ProcessorCount $ProcessorCount -StaticMemory `
    -CheckpointType Disabled -AutomaticCheckpointsEnabled $false `
    -AutomaticStartAction Start -AutomaticStartDelay 60 -AutomaticStopAction ShutDown
# Ubuntu's boot loader is signed by the Microsoft UEFI CA, not the Windows one
Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority `
    -FirstBootDevice (Get-VMHardDiskDrive -VM $vm)
Add-VMHardDiskDrive -VM $vm -Path $seedDisk
Start-VM -VM $vm

# --- Address: the Default Switch hands out a NAT address; find it by the VM's MAC --------
Write-Step 'Waiting for the VM''s address'
$ip = $null
for ($i = 0; $i -lt 40 -and -not $ip; $i++) {
    Start-Sleep -Seconds 6
    $mac = (Get-VMNetworkAdapter -VM $vm).MacAddress
    if ($mac -and $mac -ne '000000000000') {
        $dashed = ($mac -replace '(..)(?!$)', '$1-').ToUpperInvariant()
        $ip = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.LinkLayerAddress -eq $dashed -and $_.State -ne 'Unreachable' } |
            Select-Object -First 1 -ExpandProperty IPAddress
    }
}

if ($ip) {
    $reach = "ssh -J homelab ubuntu@$ip   (from the home PC; or ssh ubuntu@$ip on the laptop)"
}
else {
    $reach = "address not seen yet: open the console (vmconnect localhost $Server); cloud-init prints it there"
}
Write-Host @"

VM $Server is booting. cloud-init now runs bootstrap.sh at $RepoRef (5-10 minutes).
  Reach it:  $reach
  Wait:      cloud-init status --wait --long   (ends with: bootstrap: $Server ready)
  Next:      server/provision/README.md, "Rebuilding a server", steps 3-5, then tunnel-up.sh
"@
