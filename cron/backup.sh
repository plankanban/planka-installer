#!/bin/bash

# The archive holds secrets
umask 077

# Stop on error, including inside a pipeline
set -eo pipefail

BACKUP_DATETIME="$(date +"%Y-%m-%d_%H-%M-%S")"
INSTALL_DIR="/opt/planka"
BACKUP_DESTINATION="$INSTALL_DIR/backup"
BACKUP_TEMP="$BACKUP_DESTINATION/$BACKUP_DATETIME-backup"

PLANKA_DOCKER_CONTAINER_POSTGRES="planka_db"
PLANKA_DOCKER_CONTAINER_PLANKA="planka"

# Create temporary folder
mkdir -p "$BACKUP_TEMP"

# Dump DB into SQL file
echo -n "Exporting postgres database ... "
docker exec "$PLANKA_DOCKER_CONTAINER_POSTGRES" pg_dumpall -c -U postgres > "$BACKUP_TEMP/postgres.sql"
echo "Success!"

# Export data volume
echo -n "Exporting data volume ... "
docker run --rm --volumes-from "$PLANKA_DOCKER_CONTAINER_PLANKA" -v "$BACKUP_TEMP:/backup" node:24-alpine cp -r /app/data /backup/data
echo "Success!"

# Create tgz
echo -n "Creating final tarball $BACKUP_DATETIME-backup.tgz ... "
tar -C "$BACKUP_DESTINATION" -czf "$BACKUP_DESTINATION/$BACKUP_DATETIME-backup.tgz" \
    "$BACKUP_DATETIME-backup/postgres.sql" \
    "$BACKUP_DATETIME-backup/data"
echo "Success!"

# Remove source files
echo -n "Cleaning up temporary files and folders ... "
rm -rf "$BACKUP_TEMP"
echo "Success!"

echo "Backup Complete!"
