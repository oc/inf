# inf — e9m platform infrastructure

OpenTofu-managed VMs and DNS on the lowercase.no Proxmox cluster.

## Quick start (existing user)

```bash
# Restore age key from 1Password if not already on disk
op read "op://o19g/e9m-sops-age-key/private_key" > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Plan + apply
./tofu.sh init
./tofu.sh plan
./tofu.sh apply
```

## Quick start (new user)

See `docs/ONBOARDING.md`.

## What lives where

- `tofu/` — OpenTofu modules. Run commands via `./tofu.sh`.
- `secrets.sops.yaml` — sops-encrypted credentials. Edit with `sops secrets.sops.yaml`.
- `cloud-init/` — cloud-init templates injected into VMs at provision time.
- `docs/` — runbooks (`ARCHITECTURE.md`, `ONBOARDING.md`, `SECRETS.md`, `bootstrap-bare-metal-install-proxmox-pve.md`).
- `CLAUDE.md` — guidance for AI agents working in this repo.

## See also

- `docs/ARCHITECTURE.md` — why the stack looks the way it does
- `docs/SECRETS.md` — sops + age workflow, key rotation
- `docs/ONBOARDING.md` — clone-to-apply walkthrough
- `~/dev/infrastructure` — Salt-managed host/network layer (PVE, VyOS)
