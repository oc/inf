output "vm_inventory" {
  description = "Map of declared VMs with size + IP + node assignment. Useful for ansible/kamal targeting."
  value = {
    for name, v in local.vms : name => {
      size = v.size
      cpu  = local.vm_sizes[v.size].cores
      mem  = local.vm_sizes[v.size].memory
      disk = local.vm_sizes[v.size].disk
      ip   = v.ip
      node = v.node
      tags = v.tags
      desc = v.description
    }
  }
}

output "zones" {
  description = "Cloudflare zone IDs in this account"
  value       = local.zone_ids
}
