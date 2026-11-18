variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "test_vm_id" {
  description = "VMID voor deze testrun, binnen de 240-254 range"
  type        = number
  validation {
    condition     = var.test_vm_id >= 240 && var.test_vm_id <= 254
    error_message = "test_vm_id moet tussen 240 en 254 liggen."
  }
}
