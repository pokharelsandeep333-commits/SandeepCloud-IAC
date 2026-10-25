# modules/web-host

One public web server on EC2: the instance, an Elastic IP and its association, the key pair, a security group with its ingress and egress rules, and (optional) status-check alarms that reboot or recover the instance. `envs/prod` calls it once per server.

## Built in, not configurable

- IMDSv2 required, encrypted gp3 root volume (3000 IOPS, 125 MB/s), termination protection on.
- `prevent_destroy` and `ignore_changes = [ami, user_data]` on the instance. Lifecycle settings can't come from variables, so every server this module builds is protected. Destroying one takes a code change.
- No ingress on port 22. SSH goes over Tailscale, and the `ingress_rules` validation refuses port 22.
- Egress is open to everywhere: updates, Docker pulls, Tailscale, Let's Encrypt and upstream DNS need it. Accepted for now (`AVD-AWS-0104`); port-restricted egress gets tried in the fire drill.
- Rule descriptions are validated against the characters AWS accepts (no apostrophes), so a bad one fails at plan time instead of mid-apply.
- **Scanner skips here cover every server the module builds**: no detailed monitoring (`CKV_AWS_126`), no instance role (`CKV2_AWS_41`), and port 80 open to all (`CKV_AWS_260`, written for the Ad-Blocker). Reasons are next to each resource and in the root README.

## Inputs

| Name | What | Default |
|---|---|---|
| `name` | Short name, used in the alarm names | required |
| `instance_name` | The instance's Name tag | required |
| `ami`, `instance_type` | What to launch | required |
| `cpu_credits` | `standard` or `unlimited` | `standard` |
| `root_volume_size`, `root_volume_name` | Root volume size (GiB) and Name tag | required |
| `backup_tag` | Root volume `Backup` tag; the account's DLM policy snapshots `sandeepcloud-daily` | required |
| `subnet_id`, `vpc_id` | Where it goes | required |
| `key_name`, `public_key` | The key pair | required |
| `security_group_name`, `security_group_description` | Changing either replaces the group | required |
| `ingress_rules` | Map of `{ port, cidr, description }` TCP rules, keyed by a stable name | required |
| `status_alarms` | Create the reboot/recover alarms | `true` |

## Outputs

`instance_id`, `public_ip` (the Elastic IP), `security_group_id`.
