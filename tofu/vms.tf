# VM catalogue. Adding a new VM = adding an entry here.
locals {
  vms = {
    jumpbox = {
      size        = "nano"
      ip          = "10.100.0.1"
      node        = local.pve_nodes.pve2
      cloud_init  = "kamal-ready"
      tags        = ["jumpbox", "public"]
      description = "WireGuard server + Caddy reverse-proxy + SSH bastion. Public IP 45.89.193.11."
    }

    dev1 = {
      size        = "standard"
      ip          = "10.100.0.30"
      node        = local.pve_nodes.pve1
      cloud_init  = "kamal-ready"
      tags        = ["dev"]
      description = "Dev sandbox (dev1.e9m.tech / dev1.e9m.no)"
    }

    oc1 = {
      size        = "large"
      ip          = "10.100.0.100"
      node        = local.pve_nodes.pve1
      cloud_init  = "kamal-ready"
      tags        = ["oc"]
      description = "oc's main box (oc1.e9m.tech). LLM agent host."
    }
  }

  cloud_init_rendered = {
    for name, v in local.vms : name => templatefile(
      "${path.module}/../cloud-init/${v.cloud_init}.yaml",
      {
        hostname      = name
        fqdn          = "${name}.e9m.tech"
        oc_ssh_pubkey = local.oc_ssh_pubkey
      }
    )
  }
}

# VM resources are commented out until prerequisites are in place:
#   1. Proxmox API tokens minted (see secrets.sops.yaml -> proxmox.pveX.api_token_secret)
#   2. vmbr1 bridge exists on pve1+pve2 (see docs/ARCHITECTURE.md "Network plan")
#   3. 10.100.0.0/24 routed via VyOS (see ~/dev/infrastructure/GW/)
#   4. An Ubuntu 24.04 cloud-init template exists on each PVE node (see template.tf — TODO)
#
# resource "proxmox_virtual_environment_vm" "vm" {
#   for_each  = local.vms
#   name      = each.key
#   node_name = each.value.node
#   tags      = each.value.tags
#
#   cpu {
#     cores = local.vm_sizes[each.value.size].cores
#     type  = "host"
#   }
#   memory {
#     dedicated = local.vm_sizes[each.value.size].memory
#   }
#
#   clone {
#     vm_id = 9000  # ID of the cloud-init template VM (TODO: parameterize)
#   }
#
#   disk {
#     datastore_id = "local-zfs"
#     interface    = "scsi0"
#     size         = local.vm_sizes[each.value.size].disk
#   }
#
#   network_device {
#     bridge  = local.vm_network.bridge
#     vlan_id = local.vm_network.vlan_tag
#   }
#
#   initialization {
#     ip_config {
#       ipv4 {
#         address = "${each.value.ip}/24"
#         gateway = local.vm_network.gateway
#       }
#     }
#     user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.key].id
#   }
#
#   agent { enabled = true }
# }
#
# resource "proxmox_virtual_environment_file" "cloud_init" {
#   for_each     = local.vms
#   content_type = "snippets"
#   datastore_id = "local"
#   node_name    = each.value.node
#   source_raw {
#     data      = local.cloud_init_rendered[each.key]
#     file_name = "${each.key}.user-data.yaml"
#   }
# }
