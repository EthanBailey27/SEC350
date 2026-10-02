# main.tf - Windows Server 2025 via libvirt provider
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

# Copy the base image into the storage pool on apply, remove on destroy
resource "terraform_data" "disk" {
  input = {
    name  = "${var.student_name}-${var.vm_name}"
    image = var.image_path
  }

  provisioner "local-exec" {
    command = "sudo cp ${var.image_path} /var/lib/libvirt/images/${var.student_name}-${var.vm_name}.qcow2"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "sudo rm -f /var/lib/libvirt/images/${self.input.name}.qcow2"
  }
}

# Create the VM
resource "libvirt_domain" "windows_server" {
  name        = "${var.student_name}-${var.vm_name}"
  memory      = var.ram_size
  memory_unit = "KiB"
  vcpu        = var.cpu_cores
  type        = "kvm"
  autostart   = true

  # Added: provider 0.9.x only boots the VM on apply when running = true
  running = true

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }

  features = {
    acpi = true
    apic = {}
  }

  devices = {
    disks = [
      {
        source = {
          file = {
            file = "/var/lib/libvirt/images/${var.student_name}-${var.vm_name}.qcow2"
          }
        }
        driver = {
          type = "qcow2"
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        source = {
          network = {
            network = "default"
          }
        }
        model = {
          type = "e1000e"
        }
      }
    ]

    graphics = [
      {
        spice = {
          auto_port = true
          listen    = "0.0.0.0"
        }
      },
      # Added: a local-only VNC display so virsh vncdisplay returns a display number
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]

    serials = [
      {
        type = "pty"
      }
    ]

    consoles = [
      {
        type = "pty"
        target = {
          type = "serial"
          port = 0
        }
      }
    ]
  }

  depends_on = [
    terraform_data.disk
  ]
}
