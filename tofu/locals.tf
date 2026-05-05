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

  # VM internal network — provisioned on VyOS gw1+gw2 (committed in ~/dev/infrastructure/GW/).
  # eth1 on the gw is multi-net L2: 10.0.206/24 + 10.99.1/24 + 10.100.0/24 share the same
  # broadcast domain (no VLAN tagging). pve1/pve2's vmbr0 is on that same L2, so VMs with
  # 10.100.0.X + gw 10.100.0.254 work directly via vmbr0 — no vmbr1 needed.
  vm_network = {
    cidr     = "10.100.0.0/24"
    gateway  = "10.100.0.254" # VRRP VIP on VyOS (gw1 master at .252, gw2 backup at .253)
    bridge   = "vmbr0"        # default PVE bridge
    vlan_tag = null           # untagged
  }

  # Convenience handles
  oc_ssh_pubkey         = data.sops_file.secrets.data["ssh.oc_pubkey"]
  e9m_automation_pubkey = data.sops_file.secrets.data["ssh.e9m_automation_pubkey"]
  cf_account_id         = data.sops_file.secrets.data["cloudflare.account_id"]
  zone_ids = {
    "dialogadvokat.no" = data.sops_file.secrets.data["cloudflare.zones.dialogadvokat_no"]
    "e9m.no"           = data.sops_file.secrets.data["cloudflare.zones.e9m_no"]
    "e9m.online"       = data.sops_file.secrets.data["cloudflare.zones.e9m_online"]
    "e9m.tech"         = data.sops_file.secrets.data["cloudflare.zones.e9m_tech"]
    "equilibrium.no"   = data.sops_file.secrets.data["cloudflare.zones.equilibrium_no"]
    "irb.no"           = data.sops_file.secrets.data["cloudflare.zones.irb_no"]
    "muda.no"          = data.sops_file.secrets.data["cloudflare.zones.muda_no"]
    "o19g.com"         = data.sops_file.secrets.data["cloudflare.zones.o19g_com"]
    "perseus.no"       = data.sops_file.secrets.data["cloudflare.zones.perseus_no"]
    "rynning.no"       = data.sops_file.secrets.data["cloudflare.zones.rynning_no"]
  }
}
