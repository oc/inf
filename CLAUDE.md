# CLAUDE.md — e9m platform infrastructure

OpenTofu-based provisioning of VMs/LXCs on the lowercase.no Proxmox cluster.
Secrets via sops + age. DNS via Cloudflare. State in Cloudflare R2.

## Scope split

| Repo | Manages |
|---|---|
| `oc/inf` (this repo) | OpenTofu VM/LXC provisioning, sops secrets, cloud-init templates, DNS records, platform docs |
| `oc/infrastructure` (Salt) | Bare-metal Proxmox host config, VyOS gateways, network plumbing, SSH access lists |
| `oc/e9m` (planned) | Application code + Kamal deploy configs deployed onto VMs in this repo |

If a change is to a *VM-as-a-resource*, it lives here. If it's about the *PVE host* or *VyOS*, it's in `oc/infrastructure`.

## Layout

```
.
├── tofu/                     # OpenTofu config — run `tofu` commands from here
│   ├── main.tf               # backend (R2) + required providers + sops data source
│   ├── locals.tf             # vm_sizes, pve_nodes, vm_network
│   ├── proxmox.tf            # provider config (talks to pve1)
│   ├── cloudflare.tf         # DNS provider + record stubs
│   ├── vms.tf                # VM catalogue (jumpbox / dev1 / oc1 / ...)
│   └── outputs.tf
├── cloud-init/
│   └── kamal-ready.yaml      # cloud-init template (templatefile() consumes ${hostname} etc.)
├── secrets.sops.yaml         # sops-encrypted, single source of truth for credentials
├── .sops.yaml                # which age recipients can decrypt which files
├── docs/                     # human-readable runbooks
└── tofu.sh                   # wrapper: injects R2 creds from sops, runs `tofu` with all args
```

## Common ops

| Operation | Command |
|---|---|
| First-time setup on a new laptop | restore age key from 1Password (`o19g` vault → `e9m-sops-age-key`) to `~/.config/sops/age/keys.txt` |
| Edit secrets | `sops secrets.sops.yaml` |
| Read one secret value | `sops -d secrets.sops.yaml \| yq '.r2.access_key_id'` |
| Init tofu | `./tofu.sh init` |
| Plan changes | `./tofu.sh plan` |
| Apply changes | `./tofu.sh apply` |
| Inspect state | `./tofu.sh show` |
| Destroy a single resource | `./tofu.sh destroy -target=...` (only when explicitly authorized) |

`tofu.sh` extracts `r2.access_key_id` + `r2.secret_access_key` from sops at run time and exports them as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for the S3 backend, then `cd tofu && tofu "$@"`.

## Adding a VM

Edit `tofu/vms.tf` — add an entry to `local.vms`:

```hcl
new-vm = {
  size       = "micro"          # nano|micro|mini|standard|mid|large
  ip         = "10.100.0.42"
  node       = local.pve_nodes.pve1
  cloud_init = "kamal-ready"
  tags       = ["dev"]
  description = "..."
}
```

Then `./tofu.sh plan` → review → `./tofu.sh apply`. The new VM gets cloud-init'd with oc's SSH key + Docker + the kamal user.

## VM size catalogue

| Size | vCPU | RAM (MiB) | Disk (GiB) |
|---|---|---|---|
| nano | 1 | 2048 | 20 |
| micro | 2 | 4096 | 40 |
| mini | 2 | 8192 | 80 |
| standard | 4 | 16384 | 160 |
| mid | 8 | 32768 | 320 |
| large | 16 | 65536 | 640 |

Capacity envelope: pve1 has 320 GiB RAM / 32 threads, pve2 has 192 GiB RAM / 24 threads.

## Don'ts

- **Don't decrypt secrets to disk** — use `sops` interactively, or pipe `sops -d` to stdout. Never write decrypted output to a file in the repo.
- **Don't `tofu destroy`** without explicit user direction. Especially the jumpbox — destroying it severs WireGuard + public ingress.
- **Don't manage host-level config** (PVE itself, VyOS, switches) here — that's `oc/infrastructure`.
- **Don't add team-mate age keys** without confirming who they are with the user. Adding a recipient = giving them access to all current and future secrets.

## Topology pointers

- VM internal subnet: **10.100.0.0/24** (gw `.254`, served by VyOS gw1+gw2 VRRP VIP)
- Public ingress: **45.89.193.11** → jumpbox (10.100.0.1) via VyOS NAT
- WireGuard VPN endpoint: **45.89.193.254:51820** (lives on VyOS, peers in `~/dev/infrastructure/GW/wireguard-peers.yaml`)
- DNS zones: `e9m.no`, `e9m.tech`, `equilibrium.no` on Cloudflare (free plan)
- HTTPS: Caddy on jumpbox, Let's Encrypt DNS-01 wildcard via Cloudflare token

## Architecture decisions log

See `docs/ARCHITECTURE.md` for the **why** behind these choices. If you're tempted to refactor toward something more "professional", read that doc first — most of these are deliberate BSSN trade-offs.
