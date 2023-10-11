#!/bin/bash

# Stop on Error
set -e

BACKUP_DATETIME="$(date +"%Y-%m-%d_%H-%M-%S")"
INSTALL_DIR="/opt/planka"
BACKUP_DESTINATION="$INSTALL_DIR/backup"

PLANKA_DOCKER_CONTAINER_POSTGRES="planka_db"
PLANKA_DOCKER_CONTAINER_PLANKA="planka"


# Create Temporary folder
mkdir -p $BACKUP_DESTINATION/$BACKUP_DATETIME-backup

# Dump DB into SQL File
echo -n "Exporting postgres database ... "
docker exec -t $PLANKA_DOCKER_CONTAINER_POSTGRES pg_dumpall -c -U postgres > $BACKUP_DESTINATION/$BACKUP_DATETIME-backup/postgres.sql
echo "Success!"

# Export Docker Voumes
echo -n "Exporting user-avatars ... "
docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$BACKUP_DATETIME-backup:/backup ubuntu cp -r /app/public/user-avatars /backup/user-avatars
echo "Success!"

echo -n "Exporting project-background-images ... "
docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$BACKUP_DATETIME-backup:/backup ubuntu cp -r /app/public/project-background-images /backup/project-background-images
echo "Success!"

echo -n "Exporting attachments ... "
docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$BACKUP_DATETIME-backup:/backup ubuntu cp -r /app/private/attachments /backup/attachments
echo "Success!"

# Create tgz
echo -n "Creating final tarball $BACKUP_DATETIME-backup.tgz ... "
cd $BACKUP_DESTINATION
tar -czf $BACKUP_DESTINATION/$BACKUP_DATETIME-backup.tgz \
    $BACKUP_DATETIME-backup/postgres.sql \
    $BACKUP_DATETIME-backup/user-avatars \
    $BACKUP_DATETIME-backup/project-background-images \
    $BACKUP_DATETIME-backup/attachments
echo "Success!"

#Remove source files
echo -n "Cleaning up temporary files and folders ... "
rm -rf $BACKUP_DESTINATION/$BACKUP_DATETIME-backup
echo "Success!"

echo "Backup Complete!"