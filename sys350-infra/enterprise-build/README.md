# Enterprise Build Part I (SYS-350 Module 5)

One Terraform project that builds my whole environment on cncs212: nine Docker services on the host and three KVM VMs on their own NAT network, all from one `terraform apply`. cncs212 is shared with my lab partner, so I'm Student B. Everything is prefixed with `ebailey-`, my Docker ports are 4000-4012 and my VM subnet is 192.168.51.0/24.

## What it builds

### Docker services (kreuzwerker/docker)

| Service | Image | Network | Host port |
|---|---|---|---|
| Gitea | gitea/gitea:latest | ebailey-devops-net | 4000 |
| Draw.io | jgraph/drawio:latest | ebailey-devops-net | 4001 |
| Vaultwarden | vaultwarden/server:latest | ebailey-internal-net | 4002 |
| StirlingPDF | frooodle/s-pdf:latest | ebailey-internal-net | 4003 |
| PrivateBin | privatebin/nginx-fpm-alpine:latest | ebailey-internal-net | 4004 |
| IT-Tools (my pick) | corentinth/it-tools:latest | ebailey-devops-net | 4005 |
| MySQL | mysql:8.0 | ebailey-web-net | 4006 |
| WordPress | wordpress:latest | ebailey-web-net | 4007 |
| Uptime Kuma (my pick) | louislam/uptime-kuma:2 | ebailey-internal-net | 4008 |

The three Docker networks are separate bridges, so a container on one segment can't reach a container on another. WordPress finds MySQL by its container name (`ebailey-mysql`) on the web segment.

### KVM virtual machines (dmacvicar/libvirt)

| VM | OS | RAM | vCPU | Disk |
|---|---|---|---|---|
| ebailey-win-srv | Windows Server 2025 (Server Core) | 2 GB | 2 | Full copy of the golden image |
| ebailey-win11 | Windows 11 | 4 GB | 4 | Full copy of the golden image |
| ebailey-ubuntu-srv | Ubuntu 26.04 | 2 GB | 1 | Copy-on-write disk on the cloud image, plus cloud-init |

All three are on `ebailey-corp-lan` (192.168.51.0/24, NAT, DHCP .100-.254). The Ubuntu VM gets my user, a hashed password and an SSH key from cloud-init on first boot.

## Files

| File | What it is |
|---|---|
| main.tf | Everything: providers, variables, OS profiles, Docker and libvirt resources, outputs |
| cloud-init-server.yaml | First-boot config for the Ubuntu VM |
| .gitignore | Keeps state, tfvars and .terraform/ out of Git |
| .terraform.lock.hcl | Pins the provider versions |
| terraform.tfvars | My settings. Not in Git, there's a redacted copy below |

## How I run it

~~bash
terraform init
terraform plan
terraform apply
~~

After the first build I only edit terraform.tfvars. Adding a service or a VM is a new map entry and an apply. Removing one is deleting its entry and an apply. I don't use terraform destroy to remove one thing, since that tears down the whole build.

## Changes from the lecture code

- Student B values: ports 4000-4012 and corp_octet = 51.
- `depends_on = [docker_network.segment]` on the containers, so the networks always exist before a container tries to join one.
- No `template_format` or `format` lines in the Windows `nv_ram` block. libvirt can drop them when it saves the VM, and then Terraform marks both Windows VMs as tainted.
- An extra `deploy_private_key_openssh` output. OpenSSH can fail to load the PEM version of an ED25519 key ("invalid format"), so I SSH with the OpenSSH-format one.
- `cpu = { mode = "host-passthrough" }` on the Windows VMs. Without it libvirt gives them QEMU's basic qemu64 CPU, which doesn't have SSE4.2 or POPCNT. Windows Server 2025 and Windows 11 24H2 need both, so the VMs got stuck in an Automatic Repair loop and never got an IP. With the host CPU they boot fine.

## Host prep on cncs212

- A libvirt storage pool named `default`, since the Ubuntu volumes use it.
- `/tmp/terraform-provider-libvirt-cloudinit` set to 1777 (like /tmp), because the provider writes every user's cloud-init ISO there and two students share the box.

## Redacted terraform.tfvars

~~hcl
student_name = "ebailey"
networks     = ["devops", "internal", "web"]
corp_octet   = 51

services = {
  gitea       = { image = "gitea/gitea:latest", network = "devops", ports = [{ internal = 3000, external = 4000 }] }
  drawio      = { image = "jgraph/drawio:latest", network = "devops", ports = [{ internal = 8080, external = 4001 }] }
  vaultwarden = { image = "vaultwarden/server:latest", network = "internal", ports = [{ internal = 80, external = 4002 }], env = { ADMIN_TOKEN = "REDACTED", I_REALLY_WANT_VOLATILE_STORAGE = "true" } }
  stirlingpdf = { image = "frooodle/s-pdf:latest", network = "internal", ports = [{ internal = 8080, external = 4003 }] }
  privatebin  = { image = "privatebin/nginx-fpm-alpine:latest", network = "internal", ports = [{ internal = 8080, external = 4004 }] }
  ittools     = { image = "corentinth/it-tools:latest", network = "devops", ports = [{ internal = 80, external = 4005 }] }
  mysql       = { image = "mysql:8.0", network = "web", ports = [{ internal = 3306, external = 4006 }], env = { MYSQL_ROOT_PASSWORD = "REDACTED", MYSQL_DATABASE = "wordpress", MYSQL_USER = "wpuser", MYSQL_PASSWORD = "REDACTED" } }
  wordpress   = { image = "wordpress:latest", network = "web", ports = [{ internal = 80, external = 4007 }], env = { WORDPRESS_DB_HOST = "ebailey-mysql", WORDPRESS_DB_USER = "wpuser", WORDPRESS_DB_PASSWORD = "REDACTED", WORDPRESS_DB_NAME = "wordpress" } }
  uptimekuma  = { image = "louislam/uptime-kuma:2", network = "internal", ports = [{ internal = 3001, external = 4008 }] }
}

vms = {
  "ebailey-win-srv"    = { os = "win-server" }
  "ebailey-win11"      = { os = "win11" }
  "ebailey-ubuntu-srv" = { os = "ubuntu-server", memory_mb = 2048, vcpu = 1 }
}
~~

## Image note

My server didn't have the lecture's Windows Server 2022 image, so images.auto.tfvars (not in Git) points the Windows Server VM at the Server 2025 image from Module 3 instead:

~~~hcl
win_server_image_path = "/opt/images/win2k25.qcow2"
bios_vms              = ["ebailey-win-srv"]
~~~

VMs in bios_vms boot with BIOS instead of UEFI because their image is an MBR install. That's the only reason for the bios_vms variable and the contains() checks in the Windows domain.
