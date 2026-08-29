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
