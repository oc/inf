# Onboarding — e9m platform

How to go from a cold laptop to running `tofu apply`.

## Prerequisites

- macOS or Linux laptop with Homebrew (or apt).
- 1Password CLI (`op`) authenticated to the `uppercase.1password.com` account.
- Access to 1Password vault `o19g`.
- VyOS WireGuard peer config for your user (set up in `~/dev/infrastructure/GW/wireguard-peers.yaml`).

## Step 1 — Install toolchain

```bash
brew install opentofu sops age awscli
```

(`awscli` only needed for ad-hoc R2 ops; tofu itself uses the S3 backend natively.)

## Step 2 — Restore the age private key

```bash
mkdir -p ~/.config/sops/age
op read "op://o19g/e9m-sops-age-key/private_key" > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Verify decryption works
sops -d secrets.sops.yaml | head -5
```

If `sops -d` errors with "no key could decrypt the data": your public key isn't in `.sops.yaml`. Ask oc to add it and run `sops updatekeys secrets.sops.yaml`.

## Step 3 — Connect VPN

The platform internal subnets `10.99.1.0/24` and `10.100.0.0/24` are reachable only via the VyOS WireGuard server. Use your existing `wg-quick` config (peer pubkey + endpoint at `45.89.193.254:51820`).

```bash
sudo wg-quick up wg0
ping 10.99.1.1   # should succeed
```

## Step 4 — Initialize tofu

```bash
cd ~/O19GQ/inf
./tofu.sh init
```

`tofu.sh` extracts R2 credentials from `secrets.sops.yaml`, exports them as AWS env vars, and shells `tofu init`. State backend will be reachable; no remote backend access? Confirm step 2 succeeded.

## Step 5 — Plan + apply

```bash
./tofu.sh plan
# Review carefully. Destructive changes will be flagged with red `-` lines.
./tofu.sh apply
```

For first-ever apply: there's nothing to apply yet (VMs are commented out until prerequisites are in place — see `tofu/vms.tf` header). Plan should be a no-op.

## Step 6 — Edit secrets when needed

```bash
sops secrets.sops.yaml
# opens your $EDITOR with the decrypted contents; saves re-encrypted
```

To read a single value:
```bash
sops -d secrets.sops.yaml | yq '.r2.access_key_id'
```

## Adding a team-mate

1. They generate an age key: `age-keygen -o ~/.config/sops/age/keys.txt`
2. They send you the *public* key (the line starting with `age1...`).
3. You append it to `.sops.yaml` under `creation_rules[0].age` (comma-separated).
4. You run `sops updatekeys secrets.sops.yaml`.
5. Commit and push.
6. They store their private key in 1Password (their personal vault, or a shared one).

## Common gotchas

- **"no key could decrypt the data"**: your public age key isn't in `.sops.yaml`, OR your private key isn't at `~/.config/sops/age/keys.txt`.
- **"state lock"**: someone else's `tofu apply` is in flight, OR a previous run crashed. `./tofu.sh force-unlock <ID>` if you're sure no apply is running.
- **R2 credentials denied**: the access key in `secrets.sops.yaml` was rotated. Recreate via dashboard, update sops, re-run.
- **Plan shows changes you didn't make**: drift between state and reality (someone clicked in PVE/Cloudflare). Read carefully before applying — sometimes the right answer is `tofu refresh` or import-then-update, not blindly apply.
