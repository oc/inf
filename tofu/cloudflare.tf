# Cloudflare provider — DNS record management.
# Requires a User API Token (Zone:DNS:Edit + Zone:Zone:Edit), NOT the Account API token.
# When the user_dns_token is empty, this provider effectively no-ops (no resources reference it yet).
provider "cloudflare" {
  api_token = data.sops_file.secrets.data["cloudflare.user_dns_token"]
}

# DNS records will land in dns.tf as we add public-facing services.
# Initial records (uncomment + apply once we have the user token + jumpbox up):
#
# resource "cloudflare_record" "vpn_e9m_tech" {
#   zone_id = local.zone_ids["e9m.tech"]
#   name    = "vpn"
#   type    = "A"
#   content = "45.89.193.11"
#   proxied = false
#   ttl     = 1   # 1 = Auto on Cloudflare
# }
#
# resource "cloudflare_record" "wildcard_e9m_no" {
#   zone_id = local.zone_ids["e9m.no"]
#   name    = "*"
#   type    = "A"
#   content = "45.89.193.11"
#   proxied = false
#   ttl     = 1
# }
