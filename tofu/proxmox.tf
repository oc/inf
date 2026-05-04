# Proxmox provider — talks to pve1 as the primary endpoint. Once pve1+pve2 form a cluster,
# any node-name in resources will route correctly through this single provider config.
# Until then, target_node = pve1|pve2 directly via the bpg provider's `node_name`.
provider "proxmox" {
  endpoint = data.sops_file.secrets.data["proxmox.pve1.api_url"]
  api_token = format(
    "%s=%s",
    data.sops_file.secrets.data["proxmox.pve1.api_token_id"],
    data.sops_file.secrets.data["proxmox.pve1.api_token_secret"],
  )
  insecure = true # PVE has self-signed certs out of the box

  ssh {
    agent    = true
    username = "root"
  }
}
