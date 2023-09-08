#!/bin/sh
MAINTITLE="Planka-installer by Daniel Hiller"
INSTALL_DIR="/opt/planka"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
CONFIG_FILE=$INSTALL_DIR/.env

DOWNLOAD_URL_INSTALLER_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/installer.sh"
DOWNLOAD_URL_BACKUP_RESTORE_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/backup_restore.sh"

DOWNLOAD_URL_COMPOSE_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/docker-compose.yml"
DOWNLOAD_URL_NGINX_CONFIG_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/config/nginx-planka.conf"
DOWNLOAD_URL_BACKUP_CRON_SCRIPT_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/backup_update.sh"
DOWNLOAD_URL_FAIL2BAN_FILTER_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/config/fail2ban-filter.conf"
DOWNLOAD_URL_FAIL2BAN_JAIL_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/config/fail2ban-jail.conf"

#=======================================================================================================================

##################################
#             functions          #
##################################

function install_updates {
    echo -e "\e[1;100m####     1. System update\e[0m"
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
}


function install_packages {
    echo -e "\e[1;100m####     2. Needed packages\e[0m"
    echo -e "\e[1;104m#Installing needed packages\e[0m"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl zip snapd whois >/dev/null
    if [ $? -eq 0 ]; then
        echo -e "\e[1;32m#Package installation successfull\e[0m"
    else
        echo -e "\e[0;31m#Error while getting packages updates\e[0m"
    fi
}


function install_docker {
    echo -e "\e[1;100m####     3. Docker\e[0m"
    echo -e "\e[1;104m#Docker installation is running\e[0m"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh ./get-docker.sh >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-compose >/dev/null
    rm get-docker.sh

    ## Check docker service status
    systemctl restart docker
    sleep 5
    if
        [ "$(systemctl is-active docker)" = "active" ]; then
        echo -e "\e[1;32m#Docker installation successfull\e[0m"
    else
        echo -e "\e[0;31m#Error...cannot start Docker service\e[0m"
        exit 1
    fi
}


function install_planka {
    echo -e "\e[1;100m####     4. Installing Planka via docker-compose\e[0m"
    curl -fsSL $DOWNLOAD_URL_COMPOSE_FILE -o "$COMPOSE_FILE"
    cd "$INSTALL_DIR"
    docker-compose up -d >/dev/null
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
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null
    curl -fsSL $DOWNLOAD_URL_NGINX_CONFIG_FILE -o "/etc/nginx/sites-enabled/planka.conf"
    sed -i "s/replace/$base_url/g" /etc/nginx/sites-enabled/planka.conf

    systemctl restart nginx
    sleep 5
    if
        [ "$(systemctl is-active nginx)" = "active" ]; then
        echo -e "\e[1;32m#NGINX is installed and running\e[0m"

    else
            echo -e "\e[0;31m#Error...cannot start NGINX service\e[0m"
            exit 1
    fi
}


function install_ssl {
    echo -e "\e[1;100m####     6. Installing Lets Encrypt Cerbot\e[0m"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq snapd >/dev/null
    snap install core >/dev/null
    snap install certbot --classic >/dev/null
    ln -s /snap/bin/certbot /usr/bin/certbot

    certbot --non-interactive --agree-tos -m "$email" --nginx -d "$base_url"
}


function install_auto_backup_update {
    echo -e "\e[1;100m####     7. Installing Backup and update cronjob\e[0m"
    curl -fsSL $DOWNLOAD_URL_BACKUP_CRON_SCRIPT_FILE -o "/opt/planka/cron/backup_update.sh"
    touch $INSTALL_DIR/logs/backup-update.log
    crontab -l | { cat; echo "0 1 * * * /opt/planka/cron/backup_update.sh >> /opt/planka/log/backup-update.log 2>&1"; } | crontab -
}


function install_firewall_fail2ban {
    SSH_PORT=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter your SSH port (default: 22)" 15 60 3>&1 1>&2 2>&3 3>&-)
    clear
    echo -e "\e[1;100m####     Installing UFW and Fail2Ban\e[0m"
    echo -e "\e[1;104m#apt install is running\e[0m"

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw fail2ban >/dev/null

    echo -e "\e[1;104m#Downloading Fail2ban config\e[0m"
    curl -fsSL $DOWNLOAD_URL_FAIL2BAN_FILTER_FILE -o "/etc/fail2ban/filter.d/planka.conf"
    curl -fsSL $DOWNLOAD_URL_FAIL2BAN_JAIL_FILE -o "/etc/fail2ban/jail.d/planka.local"

    echo -e "\e[1;104m#Restarting Fail2ban\e[0m"
    systemctl restart fail2ban
    sleep 5
    if
        [ "$(systemctl is-active fail2ban)" = "active" ]; then
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
    sleep 5

    config
    echo -e "BASE_URL=https://$base_url\nSECRET_KEY=$secret_key\nDEFAULT_ADMIN_EMAIL=$email\nDEFAULT_ADMIN_NAME=$name\nDEFAULT_ADMIN_USERNAME=$username\nDEFAULT_ADMIN_PASSWORD=$password" >>"$CONFIG_FILE"
    clear
    install_updates
    install_packages
    install_docker
    install_planka
    install_proxy
    install_ssl
    install_auto_backup_update

    echo -e "\e[1;100m######################################################\e[0m"
    echo -e "\e[1;32mThe installation was completed successfully!\e[0m"
    echo -e "Open https://"$base_url" to access Planka"
    echo -e "Username: "$username""
    echo -e "Password: "$password""
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
    sleep 5

    config
    echo -e "BASE_URL=http://$base_url\nSECRET_KEY=$secret_key\nDEFAULT_ADMIN_EMAIL=$email\nDEFAULT_ADMIN_NAME=$name\nDEFAULT_ADMIN_USERNAME=$username\nDEFAULT_ADMIN_PASSWORD=$password" >>"$CONFIG_FILE"
    clear
    install_updates
    install_packages
    install_docker
    install_planka
    install_proxy
    install_auto_backup_update

    echo -e "\e[1;100m######################################################\e[0m"
    echo -e "\e[1;32mThe installation was completed successfully!\e[0m"
    echo -e "Open http://"$base_url" to access Planka"
    echo -e "Username: "$username""
    echo -e "Password: "$password""
    echo -e "\e[1;100m######################################################\e[0m"
}


function remove_planka {
    if [ -f "$COMPOSE_FILE" ]; then
        cd "$INSTALL_DIR"
        docker-compose down
        rm -R cron/ logs/ .env docker-compose.yml
        rm /etc/nginx/sites-enabled/planka
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


function config {
    mkdir -p "$INSTALL_DIR"/{cron,backup}
    mkdir -p "$INSTALL_DIR"/logs/app
    chmod -R 777 "$INSTALL_DIR"/logs/app
    touch "$CONFIG_FILE"

    base_url=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter the Domain or Subdomain, you want to use for Planka.      Do NOT enter http:// or https://).     Like planka.example.com" 15 60 3>&1 1>&2 2>&3 3>&-)
    email=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter a email address for the first admin user" 15 60 3>&1 1>&2 2>&3 3>&-)
    name=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter the name of the first admin user" 15 60 3>&1 1>&2 2>&3 3>&-)
    username=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter a username for the first admin user" 15 60 3>&1 1>&2 2>&3 3>&-)
    password=$(dialog --backtitle "$MAINTITLE" --passwordbox "Please enter a password for the first admin user" 15 60 3>&1 1>&2 2>&3 3>&-)
    password_hash=$(mkpasswd -m md5crypt "$password")
    secret_key=$(openssl rand -hex 64)

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
    clear
}

function dialog_install_firewall_fail2ban {
    dialog --title "Would you like to continue?" \
    --backtitle "$MAINTITLE" \
    --yesno "This will install UFW and Fail2Ban" 15 60
    response=$?
     case $response in
        0) install_firewall_fail2ban ;;
        1) exit_clear ;;
        255) exit_clear ;;
    esac
}


function backup {
    curl -fsSL $DOWNLOAD_URL_BACKUP_RESTORE_FILE -o /opt/backup_restore.sh
    bash /opt/backup_restore.sh
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
DIALOG_TITLE="Welcome to the Planka-Installer"
DIALOG_MENU="What should be done?"

OPTIONS=(
    1 "Install complete package"
    2 "Install complete package without ssl"
    3 "Install Firewall and Fail2ban"
    4 "Update the system"
    5 "Uninstall Planka"
    6 "Backup and restore"
    7 "Update and restart installer"
    10 "Exit"
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
    1) plankainstallercomplete ;;
    2) plankainstallerwitouthssl ;;
    3) dialog_install_firewall_fail2ban ;;
    4) dialog_system_update ;;
    5) dialog_remove_planka ;;
    6) dialog_backup ;;
    7) dialog_start_installer ;;
    10) exit_clear ;;
esac
#=======================================================================================================================