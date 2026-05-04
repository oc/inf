terraform {
  required_version = ">= 1.7"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1"
    }
  }

  # State backend: Cloudflare R2 (S3-compatible).
  # Credentials come from env (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) — wrapper script
  # `tofu.sh` extracts them from sops at run time.
  backend "s3" {
    bucket = "e9m-tofu-state"
    key    = "main.tfstate"
    region = "auto"
    endpoints = {
      s3 = "https://5f921bb1afa06518101764ccc3bcec5b.r2.cloudflarestorage.com"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}

# Decrypt secrets at plan time. Requires the age private key at
# ~/.config/sops/age/keys.txt (or SOPS_AGE_KEY_FILE env var).
data "sops_file" "secrets" {
  source_file = "${path.module}/../secrets.sops.yaml"
}
