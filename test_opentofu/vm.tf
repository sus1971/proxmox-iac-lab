resource "proxmox_virtual_environment_vm" "ci_test" {
  name      = "ci-test-${var.test_vm_id}"
  node_name = "pve"
  vm_id     = var.test_vm_id
  stop_on_destroy = true

  clone {
    vm_id = 9100
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 1024
  }

    initialization {
    ip_config {
      ipv4 {
        address = "10.20.10.${var.test_vm_id}/24"
        gateway = "10.20.10.1"
      }
    }
    user_account {
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKrCx10LNyG5RQJZxwWwrTOLEcfVYaHz9W9EiqRHDDPV ltfrank-homelab",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOosot70H7OmH/6V1qPAvZSATvRfdxFAYshh+Tp+FeQX dtfrank-homelab",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMu0caKuvWyfqSETYMNBZYMIBtb9qkabbOH0DI3oY0PX runner01-ephemeral-ci",
      ]
    }
    dns {
      servers = ["10.20.10.11", "10.20.10.12"]
      domain  = "lab.local"
    }
  }

  network_device {
    bridge = "vmbr1"
  }


}

output "ci_test_vm_id" {
  value = proxmox_virtual_environment_vm.ci_test.vm_id


}
