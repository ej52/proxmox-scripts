# Nginx Proxy Manager in Proxmox LXC container

Many benefits can be gained by using a LXC container compared to a VM. The resources needed to run a LXC container are less than running a VM. Modifing the resouces assigned to the LXC container can be done without having to reboot the container. The serial devices connected to Proxmox can be shared with multiple LXC containers simulatenously.

## Usage

***Note:*** _Before using this repo, make sure Proxmox is up to date._

To create a new LXC container on Proxmox and setup Nginx Proxy Manager to run inside of it, run the following in a SSH connection or the Proxmox web shell.

```bash
curl -sL https://raw.githubusercontent.com/ej52/proxmox/main/lxc/nginx-proxy-manager/create.sh | bash -s
```

### Command line arguments
| argument           | default              | description                                            |
|--------------------|----------------------|--------------------------------------------------------|
| --id          | $nextid                   | container id                                           |
| --bridge      | vmbr0                     | bridge used for eth0                                   |
| --cores       | 1                         | number of cpu cores                                    |
| --disksize    | 2GB                       | size of disk                                           |
| --hostname    | nginx-proxy-manager       | hostname of the container                              |
| --memory      | 512                       | amount of memory                                       |
| --storage     | local-lvm                 | storage location for container disk                    |
| --swap        | 0                         | Amount of SWAP                                         |

you can set these parameters by appending ` -- <parameter> <value>` like:

```bash
curl -sL https://raw.githubusercontent.com/ej52/proxmox/main/lxc/nginx-proxy-manager/create.sh | bash -s -- -c 4
```

## Console

There is no login required to access the console from the Proxmox web UI. If you are presented with a blank screen, press `CTRL + C` to generate a prompt.

## Thanks

- [whiskerz007](https://github.com/whiskerz007?tab=repositories)