terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113"
    }
  }

  #  backend "pg" {
  #    conn_str = "postgres://tofu@<DB-HOST>/tofu_state?sslmode=disable"
  #  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # zelfondertekend cert in het lab; niet meenemen naar productie
}
