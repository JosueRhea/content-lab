terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = { source = "digitalocean/digitalocean", version = "~> 2.40" }
    random       = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

# export DIGITALOCEAN_TOKEN=dop_v1_...
provider "digitalocean" {}
