locals {
  # Capacity tiers. Memory in MiB, disk in GiB.
  vm_sizes = {
    nano     = { cores = 1, memory = 2048, disk = 20 }    # jumpbox, exporters, single-purpose tiny
    micro    = { cores = 2, memory = 4096, disk = 40 }    # small Kamal apps
    mini     = { cores = 2, memory = 8192, disk = 80 }    # memory-leaning services
    standard = { cores = 4, memory = 16384, disk = 160 }  # dev sandboxes, multi-container apps
    mid      = { cores = 8, memory = 32768, disk = 320 }  # heavier workloads, small DB
    large    = { cores = 16, memory = 65536, disk = 640 } # LLM agents, oc1, big DB
  }

  # PVE node names as registered in the cluster (post-pve-cluster join, today they're standalone).
  pve_nodes = {
    pve1 = "pve1"
    pve2 = "pve2"
  }

  # VM internal network — provisioned on VyOS gw1+gw2, see ~/dev/infrastructure/GW/
  vm_network = {
    cidr     = "10.100.0.0/24"
    gateway  = "10.100.0.254" # VRRP VIP on VyOS
    bridge   = "vmbr1"        # Linux bridge on each PVE node
    vlan_tag = null           # null = untagged on the bridge; set if VLAN-tagged
  }

  # Convenience handles
  oc_ssh_pubkey = data.sops_file.secrets.data["ssh.oc_pubkey"]
  cf_account_id = data.sops_file.secrets.data["cloudflare.account_id"]
  zone_ids = {
    "e9m.no"         = data.sops_file.secrets.data["cloudflare.zones.e9m_no"]
    "e9m.tech"       = data.sops_file.secrets.data["cloudflare.zones.e9m_tech"]
    "equilibrium.no" = data.sops_file.secrets.data["cloudflare.zones.equilibrium_no"]
  }
}
