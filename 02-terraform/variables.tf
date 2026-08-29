variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "supabase-lab"
}

variable "instance_type" {
  description = <<-DESC
    Supabase self-host runs ~13 containers. t3.micro OOMs -- do not be tempted by
    free tier. t3.medium (4GB) is the safe live-demo floor.
  DESC
  type        = string
  default     = "t3.medium"

  validation {
    condition     = !can(regex("(nano|micro)$", var.instance_type))
    error_message = "nano/micro instances will OOM running Supabase. Use t3.small at minimum, t3.medium recommended."
  }
}

variable "root_volume_gb" {
  description = "Root disk. Docker images alone are ~8GB."
  type        = number
  default     = 30
}

variable "data_volume_gb" {
  description = "Separate EBS volume for Postgres data, so it survives instance replacement."
  type        = number
  default     = 20
}

variable "allowed_cidr" {
  description = <<-DESC
    Who can reach Supabase on :8000. Defaults to the whole internet because the
    demo needs the audience to hit it. Lock this down for anything real.
  DESC
  type        = string
  default     = "0.0.0.0/0"
}

variable "supabase_commit" {
  description = "Pinned Supabase commit/tag. Do not leave this on main for a live demo."
  type        = string
  default     = "main"
}
