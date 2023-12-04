# Nginx Proxy Manager install script

## Usage

To create a Proxmox container please follow the main [README](https://raw.githubusercontent.com/ej52/proxmox/main/README.md)

```sh
sh -c "$(wget --no-cache -qO- https://raw.githubusercontent.com/ej52/proxmox/main/install.sh)" -s --app nginx-proxy-manager
```

Run the command above to install or update [Nginx Proxy Manager](https://nginxproxymanager.com/)

***Note:*** _Only Alpine(3.12+), Debian (11+) and Ubuntu(18+) are currently supported_

### Command line arguments
| argument           | default              | description                                            |
|--------------------|----------------------|--------------------------------------------------------|
| --app         | none                      | application to install                                 |
| --cleanup     | false                     | Remove dev dependencies after install                  |