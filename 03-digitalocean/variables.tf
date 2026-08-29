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

# Two ways in, because both situations are common:
#   - you already have a key on your DO account  -> reference it by fingerprint
#   - fresh account, no keys yet                 -> let Terraform upload one
#
# Referencing is the default because DO rejects re-uploading a key it already
# has (422), and because a Terraform-managed key gets DELETED from your account
# on destroy -- unpleasant if you use that key anywhere else.

variable "create_ssh_key" {
  description = <<-DESC
    true  -> upload var.ssh_public_key to your DO account (use on a fresh account).
             NOTE: `terraform destroy` will then REMOVE that key from your account.
    false -> reference an existing key via var.ssh_key_fingerprint (default).
  DESC
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "Path to the public key to upload. Only used when create_ssh_key = true."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_key_fingerprint" {
  description = <<-DESC
    MD5 fingerprint of a key already on your DO account. Only used when
    create_ssh_key = false.

      ssh-keygen -lf ~/.ssh/id_ed25519.pub -E md5 | awk '{print $2}' | sed 's/^MD5://'

    No AWS counterpart: that build used SSM Session Manager and opened no SSH
    port at all.
  DESC
  type        = string
  default     = ""

  validation {
    condition     = var.create_ssh_key || length(var.ssh_key_fingerprint) > 0
    error_message = "Set ssh_key_fingerprint to a key already on your DO account, or set create_ssh_key = true to upload ssh_public_key."
  }
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
  description = "Pinned Supabase commit. HEAD tracks upstream's default branch (master).\n  Do not leave this unpinned for a live demo."
  type        = string
  default     = "HEAD"
}

variable "wait_for_ready" {
  description = <<-DESC
    Block `apply` until the Supabase endpoint actually answers.

    Terraform's job ends when DigitalOcean acknowledges the droplet, but cloud-init
    then runs for another 5-8 minutes. With this off, apply prints a studio_url
    that does not work yet.

    Set false to demonstrate that gap on purpose.
  DESC
  type        = bool
  default     = true
}
