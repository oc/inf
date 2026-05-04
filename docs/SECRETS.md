# Secrets — sops + age workflow

## Mental model

- **`secrets.sops.yaml`** is committed to git in encrypted form.
- **`.sops.yaml`** lists the age public keys allowed to decrypt it.
- Each user has an age **private key** at `~/.config/sops/age/keys.txt` — never committed, backed up in 1Password.
- Encryption is per-value (only the *values* in the YAML are ciphered; keys, structure, comments stay plain).

## Daily ops

| Action | Command |
|---|---|
| Edit secrets in $EDITOR (decrypts, edits, re-encrypts on save) | `sops secrets.sops.yaml` |
| Read all secrets to stdout (decrypted, never to disk) | `sops -d secrets.sops.yaml` |
| Read one path | `sops -d secrets.sops.yaml \| yq '.r2.access_key_id'` |
| Add a single key | `sops set secrets.sops.yaml '["section"]["key"]' '"value"'` |
| Re-encrypt after editing recipients | `sops updatekeys secrets.sops.yaml` |

## Adding a recipient (new team member)

1. They generate a key:
   ```bash
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```
2. They share the public line (starts with `age1...`) with you.
3. Edit `.sops.yaml`, add their pubkey to the comma-separated list:
   ```yaml
   creation_rules:
     - path_regex: \.sops\.ya?ml$
       age: >-
         age1z783fdept...,
         age1abcdef...
   ```
4. Re-encrypt to include the new recipient:
   ```bash
   sops updatekeys secrets.sops.yaml
   ```
5. `git diff` should show the encrypted blob changed but cleartext values are identical (since `sops -d` produces the same output).
6. Commit + push.

## Removing a recipient (team-mate leaves, key compromised)

1. Drop their pubkey from `.sops.yaml`.
2. `sops updatekeys secrets.sops.yaml` — re-encrypts to remaining recipients.
3. **Rotate every secret value**. The old encrypted file is in git history forever, and the departing key still decrypts it. Any value not rotated is presumed compromised.

## Rotating the age key itself

If oc's primary key is ever compromised:

1. Generate a fresh key: `age-keygen -o ~/.config/sops/age/keys-new.txt`
2. Add the new public key to `.sops.yaml` (alongside the old).
3. `sops updatekeys secrets.sops.yaml`.
4. Move `keys-new.txt` → `keys.txt`, update 1Password (`o19g/e9m-sops-age-key`).
5. Remove old public key from `.sops.yaml`.
6. `sops updatekeys` again.
7. Rotate the secret values themselves (cf. above).

## What goes in `secrets.sops.yaml` and what doesn't

**In:** API tokens, passwords, private keys, anything that grants access to anything.

**Not in:**
- Public keys (SSH pubkeys, age recipients) — those go in plain config files.
- Public IPs, hostnames, account IDs (those are in `tofu/locals.tf` or the secrets file's *unencrypted* metadata).
- Tofu state — managed separately in R2, not via sops.

The line is "could pasting this into a Slack channel get someone fired?" If yes, sops-encrypt it.

## Backup of the key itself

The age private key for this repo lives in two places:
1. `~/.config/sops/age/keys.txt` on oc's laptop.
2. 1Password vault `o19g`, item `e9m-sops-age-key`, field `private_key`.

If the laptop dies: restore from 1Password (`op read 'op://o19g/e9m-sops-age-key/private_key' > ~/.config/sops/age/keys.txt`).

If 1Password is also lost: restore from another team-mate's clone of the repo + their age key (whoever else is a recipient in `.sops.yaml`). If no team-mate yet — there is no third copy. Acceptable risk at single-user scale; revisit when team grows.
