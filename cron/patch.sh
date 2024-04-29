#!/bin/bash
### This file is used to patch existing systems
### Thats the only way to patch configs or scripts (like backup or update scripts) 
### It should be the most time empty
# 29 April 2024
DOWNLOAD_URL_CRON_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/planka-cron"
curl -fsSL $DOWNLOAD_URL_CRON_FILE -o /etc/cron.daily/planka-cron
chmod +x /etc/cron.daily/planka-cron