terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = { source = "digitalocean/digitalocean", version = "~> 2.40" }
    random       = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

# export DIGITALOCEAN_TOKEN=dop_v1_...
provider "digitalocean" {}

# =============================================================================
# NETWORK -- one VPC replaces five AWS resources
# =============================================================================

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

# =============================================================================
# SECRETS -- generated here, with nowhere safe to put them
# =============================================================================

# Same generation as the AWS build...
resource "random_id" "postgres_password" { byte_length = 24 }
resource "random_id" "jwt_secret" { byte_length = 32 }
resource "random_id" "secret_key_base" { byte_length = 32 }
resource "random_id" "vault_enc_key" { byte_length = 16 }
resource "random_id" "dashboard_password" { byte_length = 12 }

# ...but with nowhere to put them.
#
# THIS IS THE MOST IMPORTANT DIFFERENCE IN THE WHOLE BUILD.
#
# On AWS, four IAM resources gave the instance its own identity, and it fetched
# credentials from Secrets Manager at boot. Nothing sensitive was ever written
# into the launch configuration.
#
# DigitalOcean droplets have no equivalent identity and DO has no secret manager
# for droplets. So the credentials have to be injected straight into user_data --
# and DO user_data is readable for the droplet's whole life at
#     http://169.254.169.254/metadata/v1/user-data
# by ANY process on the box, root or not.
#
# We are not fixing that here; we are showing it. It is the sharpest possible
# demonstration that "just switch providers" is never just a rewrite: the AWS
# config depended on a capability that does not exist over here.
#
# Doing this properly on DO means an external secret store (Vault, Doppler,
# Infisical) -- which needs its own bootstrap token, which lands in user_data
# anyway. You reduce the blast radius; you do not eliminate it.

# =============================================================================
# STORAGE -- volume resolved by name, not ID
# =============================================================================

locals {
  # DO exposes an attached volume at /dev/disk/by-id/scsi-0DO_Volume_<name>, so
  # the name is load-bearing -- user-data resolves the device from it. The AWS
  # build did the same trick with the EBS volume ID.
  volume_name = "${var.name}-data"
}

resource "digitalocean_volume" "data" {
  name                    = local.volume_name
  region                  = var.region
  size                    = var.data_volume_gb
  initial_filesystem_type = "ext4" # DO can pre-format; on AWS we mkfs by hand
  description             = "Postgres data, outlives the droplet"
}

resource "digitalocean_volume_attachment" "data" {
  droplet_id = digitalocean_droplet.supabase.id
  volume_id  = digitalocean_volume.data.id
}

# =============================================================================
# COMPUTE -- droplet and its reserved IP
# =============================================================================

data "digitalocean_image" "ubuntu" {
  slug = "ubuntu-24-04-x64"
}

resource "digitalocean_ssh_key" "deploy" {
  name       = "${var.name}-key"
  public_key = file(pathexpand(var.ssh_public_key))
}

# AWS aws_eip -> DO reserved IP. Allocated on its own, BEFORE the droplet exists,
# so its address can be baked into user_data. That is what makes the public URLs
# correct on first boot -- the single best beat in the AWS build, and it survives
# the port intact.
resource "digitalocean_reserved_ip" "supabase" {
  region = var.region
}

resource "digitalocean_droplet" "supabase" {
  name     = var.name
  image    = data.digitalocean_image.ubuntu.slug
  region   = var.region
  size     = var.droplet_size
  vpc_uuid = digitalocean_vpc.main.id
  ssh_keys = [digitalocean_ssh_key.deploy.fingerprint]

  # DO charges separately for this and it is off by default. AWS gives you
  # CloudWatch basics for free; here you opt in.
  monitoring = true

  user_data = templatefile("${path.module}/user-data.sh", {
    region             = var.region
    public_host        = digitalocean_reserved_ip.supabase.ip_address
    supabase_commit    = var.supabase_commit
    volume_name        = local.volume_name
    postgres_password  = random_id.postgres_password.hex
    jwt_secret         = random_id.jwt_secret.hex
    secret_key_base    = random_id.secret_key_base.hex
    vault_enc_key      = random_id.vault_enc_key.hex
    dashboard_password = random_id.dashboard_password.hex
  })
}

resource "digitalocean_reserved_ip_assignment" "supabase" {
  ip_address = digitalocean_reserved_ip.supabase.ip_address
  droplet_id = digitalocean_droplet.supabase.id
}

# =============================================================================
# FIREWALL -- note: outbound is DENY-ALL once this exists
# =============================================================================

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

# =============================================================================
# READINESS -- make "apply complete" mean "Supabase actually answers"
# =============================================================================

resource "terraform_data" "ready" {
  count = var.wait_for_ready ? 1 : 0

  depends_on = [
    digitalocean_reserved_ip_assignment.supabase,
    digitalocean_volume_attachment.data,
    digitalocean_firewall.supabase,
  ]

  triggers_replace = [digitalocean_droplet.supabase.id]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -u
      IP='${digitalocean_reserved_ip.supabase.ip_address}'
      echo "Waiting for Supabase at http://$IP:8000"
      echo "First boot installs Docker and pulls ~13 images -- typically 5-8 min."
      for i in $(seq 1 150); do
        if curl -s -o /dev/null --max-time 5 "http://$IP:8000/"; then
          echo "Supabase answered after $((i * 10))s."
          exit 0
        fi
        if [ $((i % 6)) -eq 0 ]; then echo "  ... still booting, $((i * 10))s elapsed"; fi
        sleep 10
      done
      echo "Timed out after 25 min. Read the boot log:" >&2
      echo "  ssh root@$IP tail -50 /var/log/supabase-boot.log" >&2
      exit 1
    EOT
  }
}
