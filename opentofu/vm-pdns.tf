resource "proxmox_virtual_environment_vm" "pdns" {
  count     = 2
  name      = "pdns0${count.index + 1}"
  node_name = "pve"
  vm_id     = 152 + count.index

  clone {
    vm_id = 9200
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${cidrhost("10.20.10.0/24", 11 + count.index)}/24"
        gateway = "10.20.10.1"
      }
    }
    dns {
      servers = [cidrhost("10.20.10.0/24", 11 + count.index), "1.1.1.1"]
      domain  = "lab.local"
    }
  }

  network_device {
    bridge = "vmbr1"
  }
}
