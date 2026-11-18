resource "proxmox_virtual_environment_vm" "app" {
  count     = 2
  name      = "app0${count.index + 1}"
  node_name = "pve"
  vm_id     = 201 + count.index

  clone {
    vm_id = 9100
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${cidrhost("10.20.10.0/24", 51 + count.index)}/24"
        gateway = "10.20.10.1"
      }
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

resource "proxmox_virtual_environment_vm" "db01" {
  name      = "db01"
  node_name = "pve"
  vm_id     = 203

  clone {
    vm_id = 9100
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
    dedicated = 4096
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.20.10.53/24"
        gateway = "10.20.10.1"
      }
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

resource "proxmox_virtual_environment_vm" "git01" {
  name      = "git01"
  node_name = "pve"
  vm_id     = 204

  clone {
    vm_id = 9100
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.20.10.54/24"
        gateway = "10.20.10.1"
      }
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

resource "proxmox_virtual_environment_vm" "proxy01" {
  name      = "proxy01"
  node_name = "pve"
  vm_id     = 205

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
        address = "10.20.10.55/24"
        gateway = "10.20.10.1"
      }
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

resource "proxmox_virtual_environment_vm" "mon_lab01" {
  name      = "mon-lab01"
  node_name = "pve"
  vm_id     = 206

  clone {
    vm_id = 9100
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.20.10.56/24"
        gateway = "10.20.10.1"
      }
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

resource "proxmox_virtual_environment_vm" "mon_lab02" {
  name      = "mon-lab02"
  node_name = "pve"
  vm_id     = 207

  clone {
    vm_id = 9100
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.20.10.57/24"
        gateway = "10.20.10.1"
      }
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

resource "proxmox_virtual_environment_vm" "runner01" {
  name      = "runner01"
  node_name = "pve"
  vm_id     = 208

  clone {
    vm_id = 9100
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.20.10.32/24"
        gateway = "10.20.10.1"
      }
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
