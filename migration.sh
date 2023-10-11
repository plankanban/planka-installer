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


rm /opt/planka/logs/installer_update.log

if [ -f "/var/spool/cron/crontabs/root" ]; then
    rm /var/spool/cron/crontabs/root
fi

if [ -f "/var/spool/cron/root" ]; then
    rm /var/spool/cron/root
fi
