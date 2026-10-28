# server/homelab/hyperv/

SandeepCloud's **temporary home** on the homelab laptop, between AWS and the next cloud provider. The laptop has no public IP, so visitors reach it through a Cloudflare Tunnel ([`envs/cloudflare`](../../../envs/cloudflare), `sandeepcloud_origin = "tunnel"`).

[`New-SandeepCloudVM.ps1`](New-SandeepCloudVM.ps1) stands in for Terraform and the cloud. It builds a Hyper-V VM from the **same cloud-init file** the clouds get, so [`bootstrap.sh`](../../provision/bootstrap.sh) and [`restore.sh`](../../provision/restore.sh) run unchanged:

| Step | What |
|---|---|
| Image | Ubuntu 24.04 cloud image, pinned to `release-20261017`; SHA-256 checked on every run (the release's `SHA256SUMS` verified against Canonical's signing key on 2026-10-27) |
| OS disk | `qemu-img` (in WSL) converts it to a dynamic VHDX, grown to 60 GB. cloud-init grows the root partition on first boot |
| Seed | `cloud-init.yaml.tftpl` downloaded at `-RepoRef` and filled in like Terraform's `templatefile()`, on a small FAT disk labelled `CIDATA` (cloud-init's NoCloud source) |
| VM | Generation 2, Secure Boot (Microsoft UEFI CA), 2 vCPU, **2 GB fixed**, no checkpoints, on the **Default Switch**, and starts with the laptop |

**The Default Switch is NAT:** the VM can reach out, and nothing on the internet or the home Wi-Fi can reach in. The tunnel is outbound, and so is Tailscale, so the VM needs no open ports. Before Tailscale is up, the only way in is from the laptop itself, hence the `ssh -J homelab` jump below.

Files live in `C:\homelab\vms\` (outside OneDrive): the cached image in `images\`, the VM and its two disks in `sandeepcloud\`.

## Prerequisites (done 2026-10-27 unless noted)

- Hyper-V enabled, WSL capped at 6 GB (`.wslconfig`), so Wazuh and the VM both fit in the laptop's 12 GB.
- `qemu-img` in the WSL distro, once (asks for your WSL password):
  ```powershell
  wsl -d Ubuntu-24.04 -- sudo apt-get install -y qemu-utils
  ```
- The commit to build from is on `main` on GitHub. The VM clones the public repo at that commit.

## Build and restore

1. **On the laptop, in an admin PowerShell** (`-SshPublicKey` is the public key you SSH with from the home PC):
   ```powershell
   cd C:\path\to\SandeepCloud-IAC\server\homelab\hyperv
   .\New-SandeepCloudVM.ps1 -RepoRef <full commit SHA from main> -SshPublicKey "<contents of your .pub file>"
   ```
   It prints the VM's address at the end, for example `172.27.48.5`.
2. **From the home PC**, jump through the laptop and wait for cloud-init (5-10 minutes). The home PC has no default key, so name the one that matches `-SshPublicKey`:
   ```powershell
   ssh -J homelab -i ~/.ssh/homelab_ed25519 ubuntu@<VM address>
   cloud-init status --wait --long        # ends with: bootstrap: sandeepcloud ready
   ```
3. **Restore**, as in [`server/provision/README.md`](../../provision/README.md) steps 3-5. While AWS still serves the sites, use `--drill` (no Wazuh agent, no backup timers, so nothing clashes with the live server). From then on, SSH goes over Tailscale.

## Switch the sites to the tunnel

The tunnel has to exist before its token does, and the DNS should only move once `cloudflared` is connected. So the Terraform change goes in two applies (Sandeep, `envs/cloudflare`, after the [prerequisites](../../../envs/cloudflare/README.md#sandeepcloud-through-a-cloudflare-tunnel-sandeepcloud_origin): the tunnel permission on the token, `account_id`):

1. Set `sandeepcloud_origin = "tunnel"` in `terraform.tfvars`, then create **only the tunnel**:
   ```powershell
   terraform plan -out tfplan -target="cloudflare_zero_trust_tunnel_cloudflared.sandeepcloud" -target="cloudflare_zero_trust_tunnel_cloudflared_config.sandeepcloud"
   ```
   Expected: 2 to add, nothing else. Apply it.
2. Dashboard → **Networking → Tunnels → `sandeepcloud` → Add a replica**, copy the `eyJ…` token, then on the VM:
   ```bash
   sudo /home/ubuntu/SandeepCloud-IAC/server/provision/tunnel-up.sh
   ```
   It stores the token root-only, starts `cloudflared-tunnel.service`, and waits for `Registered tunnel connection`. The dashboard should show the tunnel as **Healthy**.
3. Full plan: expect `-/+` on exactly the apex, `portfolio`, `wiki` and `sentry` records (A → CNAME). Read them out loud, then apply. Check each site in a browser.

For the real move (not a drill), follow [`docs/RUNBOOK-migrate.md`](../../../docs/RUNBOOK-migrate.md): freeze, final backup on AWS, restore without `--drill`, then the switch above.

## Remove the VM

```powershell
Stop-VM sandeepcloud -TurnOff; Remove-VM sandeepcloud -Force
Remove-Item -Recurse C:\homelab\vms\sandeepcloud      # keeps the cached image in images\
```
Then delete its Tailscale node, and set `sandeepcloud_origin` back to `"ip"` once the next server has an IP.

## Limits

- **Run end to end on 2026-10-28:** the image conversion, the seed disk and the first boot, a `--drill` restore, then the real move (SandeepCloud has been live here since). After the restore, SSH goes over Tailscale. `restore.sh` now keeps the cloud-init key next to the backup's `authorized_keys` (on 2026-10-28 the backup's copy replaced it), so `-i ~/.ssh/homelab_ed25519` through the laptop still works as a fallback.
- **Home internet and power** are now SandeepCloud's uptime. That's accepted for a temporary home.
- **Same laptop as Wazuh and the rest-server.** The VM is its own Hyper-V guest, not inside Wazuh's WSL, so a compromised web app stays in the VM.
