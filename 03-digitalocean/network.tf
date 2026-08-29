# The whole AWS network stack -- VPC, internet gateway, subnet, route table, route
# table association: five resources -- collapses to this one.
#
# DigitalOcean has no subnets, no gateways and no route tables to manage. That is
# less control, not just less typing: on AWS you could have put this droplet in a
# private subnet behind a NAT. Here you cannot.
resource "digitalocean_vpc" "main" {
  name     = var.name
  region   = var.region
  ip_range = "10.42.0.0/16"
}

# AWS security group -> DO firewall. Two differences that bite:
#
#  1. A DO firewall is a standalone object that references droplets, rather than
#     something the droplet references. Inverted direction.
#  2. Outbound is DENY-ALL once a firewall exists. On AWS, egress is open until
#     you restrict it. Omit these outbound rules and the droplet cannot reach apt
#     or Docker Hub, and cloud-init hangs with no obvious cause.
resource "digitalocean_firewall" "supabase" {
  name        = "${var.name}-fw"
  droplet_ids = [digitalocean_droplet.supabase.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "8000"
    source_addresses = [var.allowed_cidr]
  }

  # No AWS equivalent: that build had no SSH port at all.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = [var.ssh_allowed_cidr]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
