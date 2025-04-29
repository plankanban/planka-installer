
# Planka Installer

Install Planka with one single command and a few questions.

## READ BEFORE INSTALL

**Do not run this installer on a server that is already in use.**

Since you need a fresh server, I recommend using Ubuntu 22.04 or Debian 12.

**Users who used the installer before October 11, 2023, should run the migration script.**

To do so, use the following command:

```bash
wget https://raw.githubusercontent.com/plankanban/planka-installer/main/migration.sh -O /opt/installer_migration.sh && bash /opt/installer_migration.sh && rm -f /opt/installer_migration.sh
```

## Features

- Installs all required packages
- Installs Planka
- Configures Nginx reverse proxy
- Automates SSL certificates
- Automates backups
- Automates updates
- Configures Fail2Ban and Firewall
- Creates the first admin user

## Roadmap

- Clean up the code
- Consider additional features

### Supported Operating Systems

| Ubuntu    | Debian    | CentOS       |
|-----------|-----------|--------------|
| 20.04     | 11        | Stream 8     |
| 22.04     | 12        | Stream 9     |

## Installation

Run the following command to start the installation process:

```bash
wget https://raw.githubusercontent.com/plankanban/planka-installer/main/installer.sh -O /opt/planka_installer.sh && bash /opt/planka_installer.sh
```

#### SSL Setup

- You must have a valid DNS entry that points to your server.
- Your server needs to be reachable on ports 80 and 443.
- A valid email address is required for SSL certificates.

## Overview

### Demo
See the installer in action: https://www.youtube.com/watch?v=0Qya8iLDnq0

![Installer](img/installer.jpeg)

## Backups
Backups will be stored here:

```bash
/opt/planka/backup
```

## Logs
Logs can be found here:

```bash
/opt/planka/logs
```

## Uninstalling / Reinstalling

You can reinstall Planka using the "Uninstall Planka" option in the installer.

### Option 1: Light
- Delete Planka containers
- Delete all Docker volumes
- Delete the Nginx configuration

### Option 2: Full (Coming Soon)
- All of Option 1
- Revoke SSL certificates (SSL Setup)
- Delete ACME accounts (SSL Setup)
- Remove all installed packages (Docker, Nginx, Certbot, etc.)
- Remove added repositories

*Note: No matter which option is chosen, backups are never deleted.*

## Some Notes

- No, I will not support your favorite Linux distribution.
- No, I will not support Windows.
- No pull requests for typo fixes.

## License

[AGPL-3.0 License](https://github.com/plankanban/planka-installer/blob/main/LICENSE)
