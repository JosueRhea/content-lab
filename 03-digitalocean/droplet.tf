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
