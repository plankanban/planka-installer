#!/bin/sh
MAINTITLE="Planka-installer by Daniel Hiller"
INSTALL_DIR="/opt/planka"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
CONFIG_FILE=$INSTALL_DIR/.env

DOWNLOAD_URL_INSTALLER_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/installer.sh"
DOWNLOAD_URL_COMPOSE_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/docker-compose.yml"

DOWNLOAD_URL_BACKUP_CRON_SCRIPT_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/backup.sh"
DOWNLOAD_URL_PATCH_CRON_SCRIPT_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/patch.sh"
DOWNLOAD_URL_PLANKA_UPDATE_CRON_SCRIPT_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/planka_update.sh"
DOWNLOAD_URL_CRON_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/planka-cron"

DOWNLOAD_URL_NGINX_CONFIG_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/config/nginx-planka.conf"
DOWNLOAD_URL_FAIL2BAN_FILTER_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/config/fail2ban-filter.conf"
DOWNLOAD_URL_FAIL2BAN_JAIL_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/config/fail2ban-jail.conf"


####BACKUP
BACKUP_DATETIME=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DESTINATION="$INSTALL_DIR/backup"

PLANKA_DOCKER_CONTAINER_POSTGRES="planka_db"
PLANKA_DOCKER_CONTAINER_PLANKA="planka"

#=======================================================================================================================

##################################
#             functions          #
##################################

function install_updates {
    echo -e "\e[1;100m####     1. System update\e[0m"

    if command -v apt-get >/dev/null; then

        echo -e "\e[1;104m#apt update is running\e[0m"
        DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
        if [ $? -eq 0 ]; then
            echo -e "\e[1;32m#Package update successfull\e[0m"
        else
            echo -e "\e[0;31m#Error while getting packages updates\e[0m"
        fi

        echo -e "\e[1;104m#apt upgrade is running\e[0m"
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null
        if [ $? -eq 0 ]; then
            echo -e "\e[1;32m#Update installation successfull\e[0m"
        else
            echo -e "\e[0;31m#Error while updating the system\e[0m"
        fi


    elif command -v yum >/dev/null; then
        echo -e "\e[1;104m#yum update is running\e[0m"
        yum install epel-release -y -q >/dev/null
        yum update -y -q >/dev/null
        if [ $? -eq 0 ]; then
            echo -e "\e[1;32m#update successfull\e[0m"
        else
            echo -e "\e[0;31m#Error while getting packages updates\e[0m"
        fi
    else
    echo -e "Your OS is not Supported"
    fi

}


function install_packages {
    echo -e "\e[1;100m####     2. Needed packages\e[0m"
    echo -e "\e[1;104m#Installing needed packages\e[0m"

    if command -v apt-get >/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl zip whois >/dev/null
        if [ $? -eq 0 ]; then
            echo -e "\e[1;32m#Package installation successfull\e[0m"
        else
            echo -e "\e[0;31m#Error while getting packages updates\e[0m"
        fi
    elif command -v yum >/dev/null; then
        yum install -y -q curl zip whois >/dev/null
        if [ $? -eq 0 ]; then
            echo -e "\e[1;32m#Package installation successfull\e[0m"
        else
            echo -e "\e[0;31m#Error while getting packages updates\e[0m"
        fi
    else
        echo -e "Your OS is not Supported"
    fi


    }


function install_docker {
    echo -e "\e[1;100m####     3. Docker\e[0m"
    echo -e "\e[1;104m#Docker installation is running\e[0m"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh ./get-docker.sh >/dev/null

    if command -v apt-get >/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-compose >/dev/null
    elif command -v yum >/dev/null; then
        yum install docker-compose-plugin -y -q >/dev/null
    else
        echo -e "Your OS is not Supported"
    fi
    systemctl enable docker --now
    rm -f get-docker.sh

    ## Check docker service status
    systemctl restart docker
    sleep 5
    if [ "$(systemctl is-active docker)" = "active" ]; then
        echo -e "\e[1;32m#Docker installation successfull\e[0m"
    else
        echo -e "\e[0;31m#Error...cannot start Docker service\e[0m"
        exit 1
    fi
}


function install_planka {
    echo -e "\e[1;100m####     4. Installing Planka via docker compose\e[0m"
    curl -fsSL $DOWNLOAD_URL_COMPOSE_FILE -o "$COMPOSE_FILE"
    cd "$INSTALL_DIR"
    docker compose up -d >/dev/null
    sleep 3

    ## Check Planka container status
    if [ "$( docker container inspect -f '{{.State.Status}}' planka )" == "running" ]; then
        echo -e "\e[1;32m#Planka is installed and running\e[0m"
    else
        dialog --backtitle "$MAINTITLE" \
        --title "ERROR" \
        --msgbox 'Planka was not startet correctly ;(' 15 60
        exit_clear
    fi
}


function install_proxy {
    echo -e "\e[1;100m####     5. Installing NGINX reverse proxy\e[0m"

    if command -v apt-get >/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null
        curl -fsSL $DOWNLOAD_URL_NGINX_CONFIG_FILE -o "/etc/nginx/sites-enabled/planka.conf"
        sed -i "s/replace/$base_url/g" /etc/nginx/sites-enabled/planka.conf

    elif command -v yum >/dev/null; then
        yum install -y -q nginx >/dev/null
        curl -fsSL $DOWNLOAD_URL_NGINX_CONFIG_FILE -o "/etc/nginx/conf.d/planka.conf"
        sed -i "s/replace/$base_url/g" /etc/nginx/conf.d/planka.conf
    else
        echo -e "Your OS is not Supported"
    fi


    systemctl enable nginx
    systemctl restart nginx
    sleep 5
    if [ "$(systemctl is-active nginx)" = "active" ]; then
        echo -e "\e[1;32m#NGINX is installed and running\e[0m"

    else
            echo -e "\e[0;31m#Error...cannot start NGINX service\e[0m"
            exit 1
    fi
}


function install_ssl {
    echo -e "\e[1;100m####     6. Installing Lets Encrypt Cerbot\e[0m"

    if command -v apt-get >/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq snapd >/dev/null
        systemctl enable --now snapd.socket
    elif command -v yum >/dev/null; then
        yum install -y -q snapd >/dev/null
        ln -s /var/lib/snapd/snap /snap
        systemctl enable --now snapd.socket >/dev/null
    else
     echo -e "Your OS is not Supported"
    fi

    sleep 3
    snap install core >/dev/null
    snap install certbot --classic >/dev/null
    ln -s /snap/bin/certbot /usr/bin/certbot

    certbot --non-interactive --agree-tos -m "$certbot_email" --nginx -d "$base_url"
}


function install_cronjobs {
    echo -e "\e[1;100m####     7. Installing cronjobs\e[0m"
    curl -fsSL $DOWNLOAD_URL_BACKUP_CRON_SCRIPT_FILE -o "/opt/planka/cron/backup.sh"
    curl -fsSL $DOWNLOAD_URL_PATCH_CRON_SCRIPT_FILE -o "/opt/planka/cron/patch.sh"
    curl -fsSL $DOWNLOAD_URL_PLANKA_UPDATE_CRON_SCRIPT_FILE -o "/opt/planka/cron/planka_update.sh"
    curl -fsSL $DOWNLOAD_URL_CRON_FILE -o /etc/cron.daily/planka-cron

    touch $INSTALL_DIR/logs/cron.log
    chmod +x /opt/planka/cron/*.sh

}


function install_firewall_fail2ban {
    SSH_PORT=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter your SSH port (default: 22)" 15 60 3>&1 1>&2 2>&3 3>&-)
    clear
    echo -e "\e[1;100m####     Installing UFW and Fail2Ban\e[0m"


    if command -v apt-get >/dev/null; then
        echo -e "\e[1;104m#apt install is running\e[0m"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw fail2ban >/dev/null
    elif command -v yum >/dev/null; then
        echo -e "\e[1;104m#yum install is running\e[0m"
        yum install -y -q ufw fail2ban >/dev/null
    else
        echo -e "Your OS is not Supported"
    fi


    echo -e "\e[1;104m#Downloading Fail2ban config\e[0m"
    curl -fsSL $DOWNLOAD_URL_FAIL2BAN_FILTER_FILE -o "/etc/fail2ban/filter.d/planka.conf"
    curl -fsSL $DOWNLOAD_URL_FAIL2BAN_JAIL_FILE -o "/etc/fail2ban/jail.d/planka.local"

    echo -e "\e[1;104m#Restarting Fail2ban\e[0m"
    systemctl restart fail2ban
    sleep 5
    if [ "$(systemctl is-active fail2ban)" = "active" ]; then
    echo -e "\e[1;32m#Fail2Ban is installed and running\e[0m"

    else
        echo -e "\e[0;31m#Error...cannot start Fail2Ban service\e[0m"
        exit 1
    fi

    echo -e "\e[1;104m#Installing Firewall rules\e[0m"
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null
    echo "y" | ufw allow "$SSH_PORT" >/dev/null
    ufw allow http >/dev/null
    ufw allow https >/dev/null
    echo "y" | ufw enable >/dev/null

    if
        [ "$(ufw status | grep "Status: active")" = "Status: active" ]; then
        echo -e "\e[1;32m#Firewall is installed and running\e[0m"

    else
        echo -e "\e[0;31m#Error...cannot start Firewall service\e[0m"
        echo "y" | ufw reset >/dev/null
        echo "y" | ufw disable >/dev/null
        exit 1
    fi
}
#=======================================================================================================================
function plankainstallercomplete {
    if [ -f "$COMPOSE_FILE" ]; then
        dialog --title "ERROR" \
        --backtitle "$MAINTITLE" \
        --msgbox 'ERROR...Planka is already installed' 15 60
        exit_clear
    fi

    echo -e "\e[1;100m####   Starting Planka installer   ####\e[0m"
    sleep 2

    config
    # echo -e "BASE_URL=https://$base_url\nSECRET_KEY=$secret_key\nDEFAULT_ADMIN_EMAIL=$email\nDEFAULT_ADMIN_NAME=$name\nDEFAULT_ADMIN_USERNAME=$username\nDEFAULT_ADMIN_PASSWORD=$password" >>"$CONFIG_FILE"
    echo -e "BASE_URL=https://$base_url\nSECRET_KEY=$secret_key" >>"$CONFIG_FILE"
    certbot_email=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter a VALID email address to issue a certificate via certbot" 15 60 3>&1 1>&2 2>&3 3>&-)
    clear
    install_updates
    install_packages
    install_docker
    install_planka
    install_proxy
    install_ssl
    install_cronjobs

    echo -e "\e[1;100m######################################################\e[0m"
    echo -e "\e[1;32mThe installation was completed successfully!\e[0m"
    echo -e "Open https://"$base_url" to access Planka"
    echo -e "Username: demo@demo.demo"
    echo -e "Password: demo"
    # echo -e "Username: $username"
    # echo -e "Password: $password"
    echo -e "\e[1;100m######################################################\e[0m"
}


function plankainstallerwitouthssl {
    if [ -f "$COMPOSE_FILE" ]; then
        dialog --title "ERROR" \
        --backtitle "$MAINTITLE" \
        --msgbox 'ERROR...Planka is already installed' 15 60
        exit_clear
    fi

    echo -e "\e[1;100m####   Starting Planka installer   ####\e[0m"
    sleep 2

    config
    # echo -e "BASE_URL=http://$base_url\nSECRET_KEY=$secret_key\nDEFAULT_ADMIN_EMAIL=$email\nDEFAULT_ADMIN_NAME=$name\nDEFAULT_ADMIN_USERNAME=$username\nDEFAULT_ADMIN_PASSWORD=$password" >>"$CONFIG_FILE"
    echo -e "BASE_URL=http://$base_url\nSECRET_KEY=$secret_key" >>"$CONFIG_FILE"

    clear
    install_updates
    install_packages
    install_docker
    install_planka
    install_proxy
    install_cronjobs

    echo -e "\e[1;100m######################################################\e[0m"
    echo -e "\e[1;32mThe installation was completed successfully!\e[0m"
    echo -e "Open http://"$base_url" to access Planka"
    echo -e "Username: demo@demo.demo"
    echo -e "Password: demo"
    # echo -e "Username: $username"
    # echo -e "Password: $password"
    echo -e "\e[1;100m######################################################\e[0m"
}


function backup {
    # Create Temporary folder
    mkdir -p $BACKUP_DESTINATION/$BACKUP_DATETIME-backup

    # Dump DB into SQL File
    echo -n "Exporting postgres database ... "
    docker exec -t $PLANKA_DOCKER_CONTAINER_POSTGRES pg_dumpall -c -U postgres > $BACKUP_DESTINATION/$BACKUP_DATETIME-backup/postgres.sql
    echo "\e[1;32mSuccess!\e[0m"

    # Export Docker Voumes
    echo -n "Exporting user-avatars ... "
    docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$BACKUP_DATETIME-backup:/backup ubuntu cp -r /app/public/user-avatars /backup/user-avatars
    echo "\e[1;32mSuccess!\e[0m"

    echo -n "Exporting project-background-images ... "
    docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$BACKUP_DATETIME-backup:/backup ubuntu cp -r /app/public/project-background-images /backup/project-background-images
    echo "\e[1;32mSuccess!\e[0m"

    echo -n "Exporting attachments ... "
    docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$BACKUP_DATETIME-backup:/backup ubuntu cp -r /app/private/attachments /backup/attachments
    echo "\e[1;32mSuccess!\e[0m"

    # Create tgz
    echo -n "Creating final tarball $BACKUP_DATETIME-backup.tgz ... "
    cd $BACKUP_DESTINATION
    tar -czf $BACKUP_DESTINATION/$BACKUP_DATETIME-backup.tgz \
        $BACKUP_DATETIME-backup/postgres.sql \
        $BACKUP_DATETIME-backup/user-avatars \
        $BACKUP_DATETIME-backup/project-background-images \
        $BACKUP_DATETIME-backup/attachments
    echo "\e[1;32mSuccess!\e[0m"

    #Remove source files
    echo -n "Cleaning up temporary files and folders ... "
    rm -rf $BACKUP_DESTINATION/$BACKUP_DATETIME-backup
    echo "\e[1;32mSuccess!\e[0m"

    echo "\e[1;32mBackup Complete!\e[0m"

    read -p "Do you want to open the installer again? (yes/no) " yn

    case $yn in
        yes) bash /opt/planka_installer.sh ;;
        no) echo exiting...;
            exit;;
        * ) echo invalid response;
            exit 1;;
    esac
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
        dialog --title "ERROR" --backtitle "$MAINTITLE" --msgbox 'ERROR...No backups available' 15 60
        dialog_backup
    else
        file=$(dialog --backtitle "$MAINTITLE" --stdout --title "Restore Planka" --cancel-label "Back" --menu "Choose a file you want to restore:" 0 0 0 "${files[@]}")
        clear

        PLANKA_BACKUP_ARCHIVE_TGZ="$file"
        PLANKA_BACKUP_ARCHIVE=$(basename $PLANKA_BACKUP_ARCHIVE_TGZ .tgz)


        # Extract tgz archive
        echo -n "Extracting tarball $PLANKA_BACKUP_ARCHIVE_TGZ ... "
        tar -xzf $PLANKA_BACKUP_ARCHIVE_TGZ
        echo "\e[1;32mSuccess!\e[0m"

        # Import Database
        echo -n "Importing postgres database ... "
        cat $PLANKA_BACKUP_ARCHIVE/postgres.sql | docker exec -i $PLANKA_DOCKER_CONTAINER_POSTGRES psql -U postgres
        echo "\e[1;32mSuccess!\e[0m"

        # Restore Docker Volumes
        echo -n "Importing user-avatars ... "
        docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$PLANKA_BACKUP_ARCHIVE:/backup ubuntu cp -rf /backup/user-avatars /app/public/
        echo "\e[1;32mSuccess!\e[0m"

        echo -n "Importing project-background-images ... "
        docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$PLANKA_BACKUP_ARCHIVE:/backup ubuntu cp -rf /backup/project-background-images /app/public/
        echo "\e[1;32mSuccess!\e[0m"

        echo -n "Importing attachments ... "
        docker run --rm --volumes-from $PLANKA_DOCKER_CONTAINER_PLANKA -v $BACKUP_DESTINATION/$PLANKA_BACKUP_ARCHIVE:/backup ubuntu cp -rf /backup/attachments /app/private/
        echo "\e[1;32mSuccess!\e[0m"

        echo -n "Cleaning up temporary files and folders ... "
        rm -R $BACKUP_DESTINATION/$PLANKA_BACKUP_ARCHIVE
        echo "\e[1;32mSuccess!\e[0m"

        echo "\e[1;32mRestore complete!\e[0m"

        read -p "Do you want to open the installer again? (yes/no) " yn

        case $yn in
            yes) bash /opt/planka_installer.sh ;;
            no) echo exiting...;
                exit;;
            * ) echo invalid response;
                exit 1;;
        esac

    fi
}


function remove_planka {
    if [ -f "$COMPOSE_FILE" ]; then
        cd "$INSTALL_DIR"
        clear
        docker compose down
        docker volume rm planka_attachments
        docker volume rm planka_project-background-images
        docker volume rm planka_user-avatars
        docker volume rm planka_db-data
        rm -Rf cron/ logs/ .env docker-compose.yml
        rm -f /etc/nginx/sites-enabled/planka.conf
        rm -f /etc/nginx/conf.d/planka.conf
        service nginx restart
        dialog --backtitle "$MAINTITLE" \
        --title "Uninstall" \
        --msgbox 'Planka and nginx config successfull deleted( Backups will stay in place)' 15 60
        exit_clear
    else
        dialog --title "Planka is not installed" \
        --backtitle "$MAINTITLE" \
        --yesno "Do you want to install Planka?" 15 60
        response=$?
        case $response in
            0) dialog_start_installer ;;
            1) exit_clear ;;
            255) exit_clear ;;
        esac
    fi
}

function remove_planka_full {
    if [ -f "$COMPOSE_FILE" ]; then
        clear
        cd "$INSTALL_DIR"
        docker compose down
        docker volume rm planka_attachments
        docker volume rm planka_project-background-images
        docker volume rm planka_user-avatars
        docker volume rm planka_db-data
        rm -Rf cron/ logs/ .env docker-compose.yml
        rm -f /etc/nginx/sites-enabled/planka.conf
        rm -f /etc/nginx/conf.d/planka.conf
            if command -v apt-get >/dev/null; then
                DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin nginx >/dev/null
                rm -f /etc/apt/sources.list.d/docker.list
                rm -f /etc/apt/keyrings/docker.gpg
                rm -rf /var/lib/docker
            elif command -v yum >/dev/null; then
                yum remove docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker-compose-plugin nginx -y -q >/dev/null
                rm -f /etc/yum.repos.d/docker-ce.repo
                rm -rf /var/lib/docker
            else
                echo -e "Your OS is not Supported"
            fi
        certbot unregister --non-interactive
        snap remove certbot
        rm -Rf /etc/letsencrypt

        dialog --backtitle "$MAINTITLE" \
        --title "Uninstall" \
        --msgbox 'Planka and all installed packages are deleted( Backups will stay in place)' 15 60
        exit_clear
    else
        dialog --title "Planka is not installed" \
        --backtitle "$MAINTITLE" \
        --yesno "Do you want to install Planka?" 15 60
        response=$?
        case $response in
            0) dialog_start_installer ;;
            1) exit_clear ;;
            255) exit_clear ;;
        esac
    fi
}

function config {
    mkdir -p "$INSTALL_DIR"/{cron,backup}
    mkdir -p "$INSTALL_DIR"/logs/{app,nginx}
    chmod -R 777 "$INSTALL_DIR"/logs/app
    touch "$CONFIG_FILE"

    base_url=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter the Domain or Subdomain, you want to use for Planka.      Do NOT enter http:// or https://).     Like planka.example.com" 15 60 3>&1 1>&2 2>&3 3>&-)
    # email=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter a email address for the first admin user" 15 60 3>&1 1>&2 2>&3 3>&-)
    # name=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter the name of the first admin user" 15 60 3>&1 1>&2 2>&3 3>&-)
    # username=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter a username for the first admin user" 15 60 3>&1 1>&2 2>&3 3>&-)
    # password=$(dialog --backtitle "$MAINTITLE" --passwordbox "Please enter a password for the first admin user" 15 60 3>&1 1>&2 2>&3 3>&-)
    # password_hash=$(mkpasswd -m md5crypt "$password")
    secret_key=$(openssl rand -hex 64)

}

function restart_planka {
    if [ -f "$COMPOSE_FILE" ]; then
        cd "$INSTALL_DIR"
        docker compose down
        docker compose up -d
        dialog_main
    else
        dialog --title "Planka is not installed" \
        --backtitle "$MAINTITLE" \
        --yesno "Do you want to install Planka?" 15 60
        response=$?
        case $response in
            0) dialog_start_installer ;;
            1) exit_clear ;;
            255) exit_clear ;;
        esac
    fi

}

function dialog_system_update {
    dialog --title "Would you like to continue?" \
    --backtitle "$MAINTITLE" \
    --yesno "All available system updates will be installed" 15 60
    response=$?
     case $response in
        0) install_updates ;;
        1) exit_clear ;;
        255) exit_clear ;;
    esac
    clear
}

function dialog_remove_planka {
    dialog --title "Would you like to continue?" \
    --backtitle "$MAINTITLE" \
    --yesno "Planka will be deleted...Are you sure? " 15 60
    response=$?
     case $response in
        0) remove_planka ;;
        1) exit_clear ;;
        255) exit_clear ;;
    esac
}


function dialog_install_firewall_fail2ban {
    dialog --title "Would you like to continue?" \
    --backtitle "$MAINTITLE" \
    --yesno "This will install UFW and Fail2Ban" 15 60
    response=$?
     case $response in
        0) install_firewall_fail2ban ;;
        1) dialog_config ;;
        255) exit_clear ;;
    esac
}
function dialog_config {
    CONFIG_MAINTITLE="Planka backup & restore by Daniel Hiller"
    CONFIG_DIALOG_TITLE="Planka backup and restore"
    CONFIG_DIALOG_MENU="What should be done?"

    CONFIG_OPTIONS=(
        1 "Install Fail2ban and Firewall"
        # 2 "Admin user settings"
        3 "Go Back"
        4 "Exit"
    )

    CONFIG_CHOICE=$(dialog --clear \
        --backtitle "$CONFIG_MAINTITLE" \
        --title "$CONFIG_DIALOG_TITLE" \
        --menu "$CONFIG_DIALOG_MENU" \
        $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_CHOICE_HEIGHT \
        "${CONFIG_OPTIONS[@]}" \
    2>&1 >/dev/tty)

    clear
    case $CONFIG_CHOICE in
        1) dialog_install_firewall_fail2ban ;;
        # 2) dialog_admin_user ;;
        3) dialog_main ;;
        4) exit_clear ;;
    esac
}

function dialog_admin_user {
    INSTALL_DIR="/opt/planka"
    CONFIG_FILE=$INSTALL_DIR/.env

    CONFIG_MAINTITLE="Planka installer by Daniel Hiller"
    CONFIG_DIALOG_TITLE="Planka Configuration"
    CONFIG_DIALOG_MENU="What should be done?"

    CONFIG_OPTIONS=(
        1 "Set Name"
        2 "Set Username"
        3 "Set Email"
        4 "Set Password"
        5 "Restart Planka"
        6 "Go Back"
        7 "Exit"
    )

    CONFIG_CHOICE=$(dialog --clear \
        --backtitle "$CONFIG_MAINTITLE" \
        --title "$CONFIG_DIALOG_TITLE" \
        --menu "$CONFIG_DIALOG_MENU" \
        $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_CHOICE_HEIGHT \
        "${CONFIG_OPTIONS[@]}" \
    2>&1 >/dev/tty)

    clear
    # && dialog --title "Success" --backtitle "$MAINTITLE" --textbox "New-Password: $password Please restart planka" 15 60


    #echo -e "BASE_URL=http://$base_url\nSECRET_KEY=$secret_key\nDEFAULT_ADMIN_EMAIL=$email\nDEFAULT_ADMIN_NAME=$name\nDEFAULT_ADMIN_USERNAME=$username\nDEFAULT_ADMIN_PASSWORD=$password" >>"$CONFIG_FILE" ;;

    case $CONFIG_CHOICE in
        1) name=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter a new name" 15 60 3>&1 1>&2 2>&3 3>&-) \
            && name_put="DEFAULT_ADMIN_NAME=$name" \
            && sed -i "s/DEFAULT_ADMIN_NAME.*/$name_put/g" "$CONFIG_FILE" \
            && dialog --title "Success" --backtitle "$MAINTITLE" --msgbox "New Name: $name Please restart Planka" 15 60 && dialog_admin_user ;;

        2) username=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter new a username" 15 60 3>&1 1>&2 2>&3 3>&-) \
            && username_put="DEFAULT_ADMIN_USERNAME=$username" \
            && sed -i "s/DEFAULT_ADMIN_USERNAME.*/$username_put/g" "$CONFIG_FILE" \
            && dialog --title "Success" --backtitle "$MAINTITLE" --msgbox "New Userame: $username Please restart Planka" 15 60 && dialog_admin_user ;;

        3) email=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter a new email address" 15 60 3>&1 1>&2 2>&3 3>&-) \
            && email_put="DEFAULT_ADMIN_EMAIL=$email" \
            && sed -i "s/DEFAULT_ADMIN_EMAIL.*/$email_put/g" "$CONFIG_FILE" \
            && dialog --title "Success" --backtitle "$MAINTITLE" --msgbox "New Email: $email Please restart Planka" 15 60 && dialog_admin_user ;;

        4) password=$(dialog --backtitle "$MAINTITLE" --passwordbox "Please enter a new password" 15 60 3>&1 1>&2 2>&3 3>&-) \
            && password_hash=$(mkpasswd -m md5crypt "$password") \
            && password_put="DEFAULT_ADMIN_PASSWORD=$password_hash" \
            && sed -i "s/DEFAULT_ADMIN_PASSWORD.*/$password_put/g" "$CONFIG_FILE" \
            && dialog --title "Success" --backtitle "$MAINTITLE" --msgbox "New Password: $password Please restart Planka" 15 60 && dialog_admin_user ;;

        5) restart_planka ;;
        6) dialog_config ;;
        7) exit_clear ;;
    esac
}

function dialog_backup {
BACKUP_MAINTITLE="Planka backup & restore by Daniel Hiller"
BACKUP_DIALOG_TITLE="Planka backup and restore"
BACKUP_DIALOG_MENU="What should be done?"

BACKUP_OPTIONS=(
    1 "Backup Planka"
    2 "Restore Planka"
    3 "Go Back"
    4 "Exit"
)

BACKUP_CHOICE=$(dialog --clear \
    --backtitle "$BACKUP_MAINTITLE" \
    --title "$BACKUP_DIALOG_TITLE" \
    --menu "$BACKUP_DIALOG_MENU" \
    $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_CHOICE_HEIGHT \
    "${BACKUP_OPTIONS[@]}" \
2>&1 >/dev/tty)

clear
case $BACKUP_CHOICE in
    1) backup ;;
    2) restore ;;
    3) dialog_main ;;
    4) exit_clear ;;
esac

}
function dialog_start_installer {
    curl -fsSL $DOWNLOAD_URL_INSTALLER_FILE -o /opt/planka_installer.sh
    bash /opt/planka_installer.sh
}

function exit_clear {
    printf "\033c"
    exit
}

#=======================================================================================================================
##################################
#         Start Dialog           #
##################################
DIALOG_HEIGHT=30
DIALOG_WIDTH=60
DIALOG_CHOICE_HEIGHT=8

function dialog_main {
    DIALOG_TITLE="Welcome to the Planka-Installer"
    DIALOG_MENU="What should be done?"

    MAIN_OPTIONS=(
        1 "Install complete package"
        2 "Install complete package without ssl"
        3 "Additional Configuration"
        4 "Backup and restore"
        5 "Update and restart installer"
        6 "Update the system"
        7 "Restart Planka"
        8 "Uninstall Planka"
        10 "Exit"
    )

    MAIN_CHOICE=$(dialog --clear \
        --backtitle "$MAINTITLE" \
        --title "$DIALOG_TITLE" \
        --menu "$DIALOG_MENU" \
        $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_CHOICE_HEIGHT \
        "${MAIN_OPTIONS[@]}" \
    2>&1 >/dev/tty)

    clear
    case $MAIN_CHOICE in
        1) plankainstallercomplete ;;
        2) plankainstallerwitouthssl ;;
        3) dialog_config ;;
        4) dialog_backup ;;
        5) dialog_start_installer ;;
        6) dialog_system_update ;;
        7) dialog_restart_planka ;;
        8) dialog_remove_planka ;;
        10) exit_clear ;;
    esac
}
#=======================================================================================================================
##################################
#         Program start         #
##################################
# Dialog installieren
export LANG=C.UTF-8

if command -v dialog >/dev/null; then
    clear
    echo -e "\e[1;100m####   Welcome to the  Planka installer   ####\e[0m"
    sleep 2
    dialog_main
elif command -v apt-get >/dev/null; then
    apt update && apt install dialog -y
    clear
    echo -e "\e[1;100m####   Welcome to the  Planka installer   ####\e[0m"
    sleep 2
    dialog_main
elif command -v yum >/dev/null; then
    yum install dialog -y
    clear
    echo -e "\e[1;100m####   Welcome to the  Planka installer   ####\e[0m"
    sleep 2
    dialog_main
else
    echo -e "Your OS is not Supported"
    exit
fi


#=======================================================================================================================