# modules/cloudflare-zone

DNS records and Email Routing rules for one Cloudflare zone. [`envs/cloudflare`](../../envs/cloudflare) calls it once.

## Built in, not configurable

- **`prevent_destroy` on every record and rule in `records`, `email_routes` and `catch_all`.** A deleted MX, SPF, DKIM or DMARC record breaks mail. Changing a record's content (a server's new IP) is an in-place update and still works. Removing a record takes a code change here first.
- **No `prevent_destroy` on `origin_records`**, the records that point at a server. Switching an A record to a tunnel CNAME changes its type, which the provider can only do by destroying and recreating it, and a server that's switched off takes its record with it.
- **Forward rules only:** each rule matches one address (`literal`, `to`) and forwards to one destination. The destinations themselves (verified, account-level addresses) stay out of Terraform.
- **Record types are validated** (A, AAAA, CNAME, MX, TXT), along with TTL (1 = Auto, or 60–86400 s) and that only A/AAAA/CNAME records are proxied, so a mistake fails at plan time.

## Inputs

| Name | What | Default |
|---|---|---|
| `zone_id` | The zone (32 hex characters) | required |
| `records` | Map of `{ name, type, content, proxied, ttl, priority }`. `name` is the full hostname. The key is the state address | required |
| `origin_records` | Same shape, A/AAAA/CNAME only, without `prevent_destroy`. Keys must not overlap with `records` | `{}` |
| `email_routes` | Map of `{ to, forward_to, enabled, name, priority }` | `{}` |
| `catch_all` | `{ enabled, action = drop or forward, forward_to, name = "" }` | required |

## Outputs

| Name | What |
|---|---|
| `record_ids` | Cloudflare record ID per key in `records` and `origin_records` |

Provider: `cloudflare/cloudflare` 5.x (`cloudflare_dns_record`, `cloudflare_email_routing_rule`, `cloudflare_email_routing_catch_all`).
