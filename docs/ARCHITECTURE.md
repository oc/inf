# Architecture — e9m platform

## What this is
Single-tenant private cloud built on two repurposed HPE servers in the Digiplex colo.
Workloads: dev sandboxes, LLM/AI agent VMs, small Kamal-deployed services. ~10 VMs target.

## Stack at a glance

```
                                Internet
                                    │
                               45.89.193.0/24
                                    │
                       ┌────────────┴────────────┐
                       │  VyOS gw1 (200) / gw2 (100)  │   ← VRRP VIPs, NAT, WG
                       └────────────┬────────────┘
                                    │
                       ┌────────────┼────────────────────────────┐
                       │                                          │
              10.99.1.0/24 (PVE host mgmt)            10.100.0.0/24 (VM internal)
                  │                                          │
       ┌──────────┴──────────┐                  ┌────────────┴────────────┐
       │                     │                  │                         │
   pve1 (Gen9)         pve2 (Gen8)          jumpbox (.0.1)        dev1 (.0.30)  oc1 (.0.100)
   ZFS-RAID-Z3         hw-RAID6+ext4        nano · public IP      standard      large
   320 GB / 32t        192 GB / 24t         WG + Caddy +          Kamal apps    LLM agents
                                            SSH bastion
```

## Tooling decisions (why these and not others)

| Concern | Pick | Reasoning |
|---|---|---|
| IaC | **OpenTofu** + `bpg/proxmox` | bpg is the actively-maintained PVE provider; native API, cloud-init friendly. Telmate is stagnant; Pulumi has thinner PVE coverage |
| Secrets | **sops + age** | age keys are simpler than GPG; partial YAML encryption; no centralized vault to operate |
| State | **Cloudflare R2** (S3-compat) | Already in the stack via DNS, free 10 GB tier covers state files for years |
| DNS | **Cloudflare free** | Already used for `wg18.no`, well-known patterns, generous free tier, DNS-01 ACME |
| Reverse proxy | **Caddy** with Cloudflare DNS-01 | One config file. Automatic Let's Encrypt wildcard. Fewer moving parts than nginx+certbot or Traefik |
| VPN | **plain WireGuard** (`wg-quick`) | Existing setup in `~/dev/infrastructure/GW/`; no control plane to add |
| App deploy | **Kamal** | Already used elsewhere in the org |

Things explicitly **rejected** for now: Pulumi (smaller ecosystem), Ansible as primary config layer (cloud-init suffices), NixOS (steep onboarding), Headscale (premature), Traefik (more YAML for less benefit at this scale).

## Why two repos (`oc/inf` + `oc/infrastructure`)

`oc/infrastructure` is Salt-based, manages bare-metal hosts (PVE OS install, VyOS configs, internal DNS). It's the layer below.

`oc/inf` (this repo) is OpenTofu-based, manages the VMs that *run on* that bare-metal layer + the public DNS. It's a layer above.

Mixing them would force one tool's mental model onto the other's domain. Salt is good for "ensure this file/package/state exists on this host"; tofu is good for "this VM exists with these specs". Different idioms.

## VM size catalogue rationale

The hunch in the kickoff message was 1:4 vCPU:RAM at every tier. Adjusted to:

- `nano` ≠ "small VM with lots of RAM" — it's "single-purpose tiny" (jumpbox, exporters). 2 GB is plenty.
- `large` added because LLM-agent workloads + DBs need a tier above `mid` and 320 GiB pve1 RAM accommodates two of them.
- Disk tiers in powers of 2 (`20/40/80/160/320/640`) — easier on the eye, snapshots stay reasonable on ZFS.

Memory ratio `1:4` matches AWS m-series and Hetzner CX defaults — sensible default if you don't know what you'll run yet.

## Network topology

Three subnets, three roles:

| Subnet | Role | Gateway | Notes |
|---|---|---|---|
| 10.0.206.0/24 | iLO / mgmt | n/a | Physical mgmt switch. Direct iLO access only. |
| 10.99.1.0/24 | PVE host OS | 10.99.1.254 (VRRP) | The Proxmox hypervisors live here. SSH from oc-VPN only. |
| 10.100.0.0/24 | VM internal | 10.100.0.254 (VRRP) | All VMs go here. Public IP 45.89.193.11 1:1 NAT'd to 10.100.0.1 (jumpbox). |

VyOS gw1 + gw2 do VRRP failover for `.254` on each subnet, NAT-masquerade outbound, WireGuard-server `45.89.193.254:51820`.

The `oc` WG peer's `allowed_networks` already includes `10.0.0.0/8` so 10.100.0.0/24 is reachable from the Mac via VPN once the VyOS interface alias is in place.

## Secret topology

```
┌──────────────────────┐    encrypts to    ┌──────────────────────┐
│ secrets.sops.yaml    │ ◄──────────────── │ age public key       │
│ (committed to git)   │                   │ (in .sops.yaml)      │
└──────────┬───────────┘                   └──────────────────────┘
           │ decrypts with
           ▼
┌──────────────────────┐
│ ~/.config/sops/age/  │  ◄─ stored in 1Password (vault o19g, item e9m-sops-age-key)
│   keys.txt (private) │
└──────────────────────┘
```

Adding a team-mate: append their age public key to `.sops.yaml`, run `sops updatekeys secrets.sops.yaml`. They restore their private key separately.

Removing a team-mate: drop their public key from `.sops.yaml`, `sops updatekeys`, **rotate every secret** (their old laptop still has the old encrypted file).

## What's not here

- **Backups**: deferred. Tier-1 (PBS in colo) and tier-2 (Backblaze B2 offsite) sketched in `docs/BACKUPS.md` (TODO when we have >5 VMs).
- **Monitoring/alerting**: out of scope for v0. Use Proxmox web UI dashboards.
- **HA**: single jumpbox = single point of public-ingress failure. Acceptable for a small ops setup. Document, plan future.
- **Multi-environment**: there is no dev/staging/prod split. The repo is the single environment. Branch + workspace if we ever need it.
- **CI/CD for tofu**: changes are applied from oc's laptop. Add CI when team grows past 1.

## What changes vs. `~/dev/infrastructure`'s patterns

We deliberately *don't* port:
- Salt's nested `pillar/<env>/<service>/<host>.sls` hierarchy → flattened into `tofu/locals.tf` + a single `secrets.sops.yaml`.
- Salt's `top.sls` host-to-role mapping → expressed as `cloud_init: "kamal-ready"` per VM in `vms.tf`.

We *do* port:
- Hostname conventions (`pve1`, `dev1`, `oc1`).
- WireGuard topology + `oc` peer pubkey (already in upstream).
- IP scheme conventions (`.1` = gateway, `.30` / `.100` = specific hosts).
