#!/bin/bash

# Stop on Error
set -e

PLANKA_DOCKER_CONTAINER_POSTGRES="planka_db"
PLANKA_DOCKER_CONTAINER_PLANKA="planka"
BACKUP_DESTINATION=/opt/planka/backup


function backup {

# Create Temporary folder
BACKUP_DATETIME=$(date +"%Y-%m-%d_%H-%M-%S")
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

}

function restore {

cd $BACKUP_DESTINATION

files=() #blank the variable so its empty for next use
# Loop folder, add files to array
while IFS= read -r -d $'\0' file; do
    files+=("$file" "")
done < <(find "$BACKUP_DESTINATION" -maxdepth 1 -type f -name "*.tgz" -print0)
# or for all files: done < <(find "$BACKUP_DESTINATION" -maxdepth 1 -type f -print0)
# Check it has at least 1 file to show (otherwise dialog errors)
if [ ${#files[@]} -eq 0 ]; then
    clear
    echo "No backup files found in $directory"
else
    file=$(dialog --stdout --title "Restore Planka" --cancel-label "Back" --menu "Choose a file you want to restore:" 0 0 0 "${files[@]}")
    clear
fi

# Extract tgz archive
PLANKA_BACKUP_ARCHIVE_TGZ="$file"
PLANKA_BACKUP_ARCHIVE=$(basename $PLANKA_BACKUP_ARCHIVE_TGZ .tgz)
echo -n "Extracting tarball $PLANKA_BACKUP_ARCHIVE_TGZ ... "
tar -xzf $PLANKA_BACKUP_ARCHIVE_TGZ
echo "Success!"

# Import Database
echo -n "Importing postgres database ... "
cat $PLANKA_BACKUP_ARCHIVE/postgres.sql | docker exec -i $PLANKA_DOCKER_CONTAINER_POSTGRES psql -U postgres
echo "Success!"

# Restore Docker Volumes
echo -n "Importing user-avatars ... "
docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$PLANKA_BACKUP_ARCHIVE:/backup ubuntu cp -rf /backup/user-avatars /app/public/
echo "Success!"
echo -n "Importing project-background-images ... "
docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$PLANKA_BACKUP_ARCHIVE:/backup ubuntu cp -rf /backup/project-background-images /app/public/
echo "Success!"
echo -n "Importing attachments ... "
docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$PLANKA_BACKUP_ARCHIVE:/backup ubuntu cp -rf /backup/attachments /app/private/
echo "Success!"

echo -n "Cleaning up temporary files and folders ... "

rm -R $BACKUP_DESTINATION/$PLANKA_BACKUP_ARCHIVE
echo "Success!"

echo "Restore complete!"

}


function exit_clear {
    printf "\033c"
    exit
}

#=======================================================================================================================

##################################
#         Program start         #
##################################

# Dialog installieren
apt update
apt install dialog
export LANG=C.UTF-8

#=======================================================================================================================


##################################
#         Start Dialog           #
##################################

DIALOG_HEIGHT=30
DIALOG_WIDTH=60
DIALOG_CHOICE_HEIGHT=8
DIALOG_TITLE="Planka backup and restore"
DIALOG_MENU="What should be done?"

OPTIONS=(
    1 "Backup Planka"
    2 "Restore Planka"
    3 "Exit"
)

CHOICE=$(dialog --clear \
    --backtitle "$MAINTITLE" \
    --title "$DIALOG_TITLE" \
    --menu "$DIALOG_MENU" \
    $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_CHOICE_HEIGHT \
    "${OPTIONS[@]}" \
2>&1 >/dev/tty)

clear
case $CHOICE in
    1) backup ;;
    2) restore ;;
    3) exit_clear ;;
esac

#=======================================================================================================================
