#!/usr/bin/env bash
# Wrapper around `tofu` that injects R2 backend credentials from sops at run time.
# Reads ~/.config/sops/age/keys.txt — fail fast if missing.

set -euo pipefail

cd "$(dirname "$0")"

if [ ! -s "${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" ]; then
    echo "✗ age private key not found at ${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" >&2
    echo "  restore with: op read 'op://o19g/e9m-sops-age-key/private_key' > ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt" >&2
    exit 1
fi

# Decrypt once, reuse via env exports.
secrets=$(sops -d secrets.sops.yaml)

export AWS_ACCESS_KEY_ID=$(echo "$secrets" | awk '/^r2:/{f=1} f && /access_key_id:/{print $2; exit}' | tr -d '"')
export AWS_SECRET_ACCESS_KEY=$(echo "$secrets" | awk '/^r2:/{f=1} f && /secret_access_key:/{print $2; exit}' | tr -d '"')

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "✗ failed to extract R2 credentials from secrets.sops.yaml" >&2
    exit 1
fi

cd tofu
exec tofu "$@"
