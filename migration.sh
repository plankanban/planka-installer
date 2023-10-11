#!/bin/bash

# Stop on Error
set -e

INSTALL_DIR="/opt/planka"

DOWNLOAD_URL_BACKUP_CRON_SCRIPT_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/backup.sh"
DOWNLOAD_URL_PLANKA_UPDATE_CRON_SCRIPT_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/planka_update.sh"
DOWNLOAD_URL_CRON_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/planka-cron"


curl -fsSL $DOWNLOAD_URL_BACKUP_CRON_SCRIPT_FILE -o "/opt/planka/cron/backup.sh"
curl -fsSL $DOWNLOAD_URL_PLANKA_UPDATE_CRON_SCRIPT_FILE -o "/opt/planka/cron/planka_update.sh"
curl -fsSL $DOWNLOAD_URL_CRON_FILE -o /etc/cron.daily/planka-cron




touch $INSTALL_DIR/logs/cron.log
chmod +x /opt/planka/cron/*.sh
chmod +x /etc/cron.daily/planka-cron

rm -f /opt/planka/logs/installer_update.log /opt/planka/cron/backup_update.sh /var/spool/cron/crontabs/root /var/spool/cron/root
