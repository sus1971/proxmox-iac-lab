terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113"
    }
  }
  # Bewust GEEN backend-block hier — lokale state, apart van de
  # PostgreSQL-backend van de hoofdinfrastructuur. Tijdelijke
  # test-VM's horen niet in de permanente centrale state.
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}
