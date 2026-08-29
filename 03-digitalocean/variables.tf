variable "region" {
  description = "DO region slug: nyc3, sfo3, fra1, lon1, ams3, sgp1, tor1, blr1, syd1."
  type        = string
  default     = "nyc3"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "supabase-lab"
}

variable "droplet_size" {
  description = <<-DESC
    Size slug. Supabase self-host runs ~13 containers, so 4GB is the floor --
    the same constraint as the AWS build, expressed in a different vocabulary.
  DESC
  type        = string
  default     = "s-2vcpu-4gb"

  validation {
    condition     = !contains(["s-1vcpu-1gb", "s-1vcpu-2gb", "s-2vcpu-2gb"], var.droplet_size)
    error_message = "That droplet is too small; the containers will OOM. Use s-2vcpu-4gb or larger."
  }
}

variable "data_volume_gb" {
  description = "Block-storage volume for Postgres data, so it outlives the droplet."
  type        = number
  default     = 20
}

variable "ssh_public_key" {
  description = <<-DESC
    Path to the public key allowed to SSH in.

    Note this variable has no AWS counterpart: that build used SSM Session Manager
    and opened no SSH port at all. DigitalOcean has no equivalent, so SSH is the
    only way in. See docs/aws-vs-digitalocean.md.
  DESC
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_allowed_cidr" {
  description = "Who may reach :22. Narrow this -- it is a real open port, unlike the AWS build."
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_cidr" {
  description = "Who may reach Supabase on :8000. Open, so the audience can hit it."
  type        = string
  default     = "0.0.0.0/0"
}

variable "supabase_commit" {
  description = "Pinned Supabase commit. Do not leave this on main for a live demo."
  type        = string
  default     = "main"
}
