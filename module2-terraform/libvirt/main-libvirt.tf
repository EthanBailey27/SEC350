# Complete libvirt stack - replaces Module 1 manual KVM commands
# All resource names use ${var.student_name}- prefix for shared server isolation

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Shared server: your student identifier prefixes all resource names
variable "student_name" {
  type        = string
  description = "Your student identifier (e.g., jsmith, mgarcia)"

  validation {
    condition     = can(regex("^[a-z]{2,10}$", var.student_name))
    error_message = "Student name must be 2-10 lowercase letters."
  }
}

variable "vm_memory" {
  description = "VM memory in KiB"
  type        = number
  default     = 1048576 # 1 GB
}

variable "vm_vcpu" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 4
}

# Network (replaces virsh net-define lan.xml + virsh net-start lan)
# +1 partner: 192.168.101.x so it can't collide with my partner's 192.168.100.x
resource "libvirt_network" "lan" {
  name      = "${var.student_name}-lan"
  autostart = true

  forward = {
    mode = "nat"
  }

  ips = [
    {
      address = "192.168.101.1"
      prefix  = 24
      family  = "ipv4"

      # DHCP range for automatic IP assignment
      dhcp = {
        ranges = [
          {
            start = "192.168.101.100"
            end   = "192.168.101.254"
          }
        ]
      }
    }
  ]
}

# Storage pool (replaces virsh pool-define-as default dir /var/lib/libvirt/images)
# The permissions block ensures QEMU can read the images directory
# Shared server: my own folder, outside the images folder my partner's pool uses
resource "libvirt_pool" "default" {
  name = "${var.student_name}-default"
  type = "dir"

  target = {
    path = "/var/lib/libvirt/${var.student_name}-images"
    permissions = {
      owner = 64055
      group = 64055
      mode  = "0750"
    }
  }
}

# Base image (replaces wget + manual qcow2 download)
resource "libvirt_volume" "ubuntu_base" {
  name = "${var.student_name}-ubuntu-base.qcow2"
  pool = "${var.student_name}-default"
  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    }
  }

  depends_on = [libvirt_pool.default]
}

# VM disk (replaces virt-install --disk)
resource "libvirt_volume" "ubuntu_disk" {
  name     = "${var.student_name}-ubuntu-server.qcow2"
  pool     = libvirt_pool.default.name
  capacity = 42949672960 # 40 GB

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}

# VM (replaces virt-install + virsh define)
resource "libvirt_domain" "ubuntu_server" {
  name   = "${var.student_name}-ubuntu-server"
  memory = var.vm_memory
  vcpu   = var.vm_vcpu
  type   = "kvm"

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = "${var.student_name}-default"
            volume = libvirt_volume.ubuntu_disk.name
          }
        }
        target = {
          bus = "virtio"
          dev = "vda"
        }
        driver = {
          type = "qcow2"
        }
      }
    ]

    interfaces = [
      {
        type  = "network"
        model = { type = "virtio" }
        source = {
          network = {
            network = libvirt_network.lan.name
          }
        }
      }
    ]

    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]
  }

  running = true
}

output "network_name" {
  description = "Name of the libvirt network"
  value       = libvirt_network.lan.name
}

output "vm_name" {
  description = "Name of the VM"
  value       = libvirt_domain.ubuntu_server.name
}
