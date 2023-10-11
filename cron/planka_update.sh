#!/bin/bash

# Stop on Error
set -e

echo -n "Updating Planka...."
cd $INSTALL_DIR
docker compose pull
docker compose --env-file .env up -d

echo "Update Complete"