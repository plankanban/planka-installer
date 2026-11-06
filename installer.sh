#!/bin/bash
MAINTITLE="Planka-installer by Daniel Hiller"
INSTALL_DIR="/opt/planka"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
CONFIG_FILE="$INSTALL_DIR/.env"

DOWNLOAD_URL_INSTALLER_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/installer.sh"
DOWNLOAD_URL_COMPOSE_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/docker-compose.yml"

DOWNLOAD_URL_BACKUP_CRON_SCRIPT_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/backup.sh"
DOWNLOAD_URL_PATCH_CRON_SCRIPT_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/patch.sh"
DOWNLOAD_URL_PLANKA_UPDATE_CRON_SCRIPT_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/planka_update.sh"
DOWNLOAD_URL_CRON_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/cron/planka-cron"

DOWNLOAD_URL_NGINX_CONFIG_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/config/nginx-planka.conf"
DOWNLOAD_URL_FAIL2BAN_FILTER_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/config/fail2ban-filter.conf"
DOWNLOAD_URL_FAIL2BAN_JAIL_FILE="https://raw.githubusercontent.com/plankanban/planka-installer/main/config/fail2ban-jail.conf"

BACKUP_DESTINATION="$INSTALL_DIR/backup"

PLANKA_DOCKER_CONTAINER_POSTGRES="planka_db"
PLANKA_DOCKER_CONTAINER_PLANKA="planka"

#=======================================================================================================================

##################################
#             functions          #
##################################

function require_supported_os {
    local id version
    id=$(. /etc/os-release 2>/dev/null && echo "$ID")
    version=$(. /etc/os-release 2>/dev/null && echo "$VERSION_ID")

    if [ "$id $version" != "debian 13" ] && [ "$id $version" != "ubuntu 26.04" ]; then
        echo -e "\e[0;31m#Unsupported OS: ${id:-unknown} ${version}. The installer supports Debian 13 and Ubuntu 26.04 LTS only.\e[0m"
        exit 1
    fi
}

function install_updates {
    echo -e "\e[1;100m####     1. System update\e[0m"

    echo -e "\e[1;104m#apt update is running\e[0m"
    if DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null; then
        echo -e "\e[1;32m#Package update successfull\e[0m"
    else
        echo -e "\e[0;31m#Error while getting packages updates\e[0m"
    fi

    echo -e "\e[1;104m#apt upgrade is running\e[0m"
    if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null; then
        echo -e "\e[1;32m#Update installation successfull\e[0m"
    else
        echo -e "\e[0;31m#Error while updating the system\e[0m"
    fi
}


function install_packages {
    echo -e "\e[1;100m####     2. Needed packages\e[0m"
    echo -e "\e[1;104m#Installing needed packages\e[0m"

    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl openssl ca-certificates >/dev/null; then
        echo -e "\e[1;32m#Package installation successfull\e[0m"
    else
        echo -e "\e[0;31m#Error while installing packages\e[0m"
        exit 1
    fi
}


function install_docker {
    echo -e "\e[1;100m####     3. Docker\e[0m"
    echo -e "\e[1;104m#Docker installation is running\e[0m"

    local script
    script=$(mktemp)
    if ! curl -fsSL https://get.docker.com -o "$script" || ! sh "$script" >/dev/null; then
        rm -f "$script"
        echo -e "\e[0;31m#Error...cannot install Docker\e[0m"
        exit 1
    fi
    rm -f "$script"

    systemctl enable docker --now
    systemctl restart docker
    sleep 5
    if [ "$(systemctl is-active docker)" = "active" ] && docker compose version >/dev/null 2>&1; then
        echo -e "\e[1;32m#Docker installation successfull\e[0m"
    else
        echo -e "\e[0;31m#Error...cannot start Docker service\e[0m"
        exit 1
    fi
}


function install_planka {
    echo -e "\e[1;100m####     4. Installing Planka via docker compose\e[0m"

    if ! curl -fsSL "$DOWNLOAD_URL_COMPOSE_FILE" -o "$COMPOSE_FILE"; then
        echo -e "\e[0;31m#Error...cannot download docker-compose.yml\e[0m"
        exit 1
    fi
    cd "$INSTALL_DIR" || exit 1

    if ! docker compose up -d >/dev/null; then
        echo -e "\e[0;31m#Error...docker compose up failed\e[0m"
        exit 1
    fi

    ## Wait for the container health check
    local status="" i
    for ((i = 0; i < 90; i++)); do
        status=$(docker container inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' planka 2>/dev/null)
        [ "$status" = "healthy" ] && break
        sleep 2
    done

    if [ "$status" = "healthy" ]; then
        echo -e "\e[1;32m#Planka is installed and running\e[0m"
    else
        local logs
        logs=$(docker logs --tail 20 planka 2>&1)
        dialog --backtitle "$MAINTITLE" \
        --title "ERROR" \
        --msgbox "Planka did not become healthy within 180 seconds (status: ${status:-unknown}).\n\nLast log lines:\n$logs" 25 76
        exit_clear
    fi
}


function install_proxy {
    echo -e "\e[1;100m####     5. Installing NGINX reverse proxy\e[0m"

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null
    if ! curl -fsSL "$DOWNLOAD_URL_NGINX_CONFIG_FILE" -o "/etc/nginx/sites-enabled/planka.conf"; then
        echo -e "\e[0;31m#Error...cannot download NGINX config\e[0m"
        exit 1
    fi
    sed -i "s/server_name replace;/server_name $base_url;/" /etc/nginx/sites-enabled/planka.conf

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

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-nginx >/dev/null

    if ! certbot --non-interactive --agree-tos -m "$certbot_email" --nginx -d "$base_url"; then
        echo -e "\e[0;31m#Error...certbot could not issue a certificate. Check that the DNS entry of $base_url points to this server and that ports 80 and 443 are reachable.\e[0m"
        exit 1
    fi
}


function install_cronjobs {
    echo -e "\e[1;100m####     7. Installing cronjobs\e[0m"
    curl -fsSL $DOWNLOAD_URL_BACKUP_CRON_SCRIPT_FILE -o "/opt/planka/cron/backup.sh"
    curl -fsSL $DOWNLOAD_URL_PATCH_CRON_SCRIPT_FILE -o "/opt/planka/cron/patch.sh"
    curl -fsSL $DOWNLOAD_URL_PLANKA_UPDATE_CRON_SCRIPT_FILE -o "/opt/planka/cron/planka_update.sh"
    curl -fsSL $DOWNLOAD_URL_CRON_FILE -o /etc/cron.daily/planka-cron

    touch $INSTALL_DIR/logs/cron.log
    chmod +x /opt/planka/cron/*.sh
    chmod +x /etc/cron.daily/planka-cron
}


function install_firewall_fail2ban {
    SSH_PORT=$(dialog --backtitle "$MAINTITLE" --inputbox "Please enter your SSH port (default: 22)" 15 60 3>&1 1>&2 2>&3 3>&-)
    clear
    # An empty or invalid port would lock the user out
    [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || SSH_PORT=22
    echo -e "\e[1;100m####     Installing UFW and Fail2Ban\e[0m"

    echo -e "\e[1;104m#apt install is running\e[0m"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw fail2ban >/dev/null

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

    if ufw status | grep -q "Status: active"; then
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
    require_supported_os

    if [ -f "$COMPOSE_FILE" ]; then
        dialog --title "ERROR" \
        --backtitle "$MAINTITLE" \
        --msgbox 'ERROR...Planka is already installed' 15 60
        exit_clear
    fi

    echo -e "\e[1;100m####   Starting Planka installer   ####\e[0m"
    sleep 2

    config
    ask_required certbot_email "Please enter a VALID email address to issue a certificate via certbot"
    write_config "https"
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
    echo -e "Open https://$base_url to access Planka"
    echo -e "Username: $username"
    echo -e "Password: $password"
    echo -e "\e[1;100m######################################################\e[0m"
}


function plankainstallerwitouthssl {
    require_supported_os

    if [ -f "$COMPOSE_FILE" ]; then
        dialog --title "ERROR" \
        --backtitle "$MAINTITLE" \
        --msgbox 'ERROR...Planka is already installed' 15 60
        exit_clear
    fi

    echo -e "\e[1;100m####   Starting Planka installer   ####\e[0m"
    sleep 2

    config
    write_config "http"
    clear
    install_updates
    install_packages
    install_docker
    install_planka
    install_proxy
    install_cronjobs

    echo -e "\e[1;100m######################################################\e[0m"
    echo -e "\e[1;32mThe installation was completed successfully!\e[0m"
    echo -e "Open http://$base_url to access Planka"
    echo -e "Username: $username"
    echo -e "Password: $password"
    echo -e "\e[1;100m######################################################\e[0m"
}


function backup {
    if [ ! -x /opt/planka/cron/backup.sh ]; then
        echo -e "\e[0;31mBackup script /opt/planka/cron/backup.sh not found. Is Planka installed?\e[0m"
        exit 1
    fi

    if ! /opt/planka/cron/backup.sh; then
        echo -e "\e[0;31mBackup failed!\e[0m"
        exit 1
    fi

    read -p "Do you want to open the installer again? (yes/no) " yn

    case $yn in
        yes) bash /opt/planka_installer.sh ;;
        no) echo "exiting...";
            exit;;
        * ) echo "invalid response";
            exit 1;;
    esac
}


function restore_fail {
    echo -e "\e[0;31m$1\e[0m"
    [ -n "$RESTORE_TMP" ] && rm -rf "$RESTORE_TMP"
    exit 1
}


function restore {
    local files=() file rc entries

    # Loop folder, add files to array
    while IFS= read -r -d $'\0' file; do
        files+=("$file" "")
    done < <(find "$BACKUP_DESTINATION" -maxdepth 1 -type f -name "*.tgz" -print0 | sort -z)
    # Check it has at least 1 file to show (otherwise dialog errors)
    if [ ${#files[@]} -eq 0 ]; then
        clear
        dialog --title "ERROR" --backtitle "$MAINTITLE" --msgbox 'ERROR...No backups available' 15 60
        dialog_backup
        return
    fi

    file=$(dialog --backtitle "$MAINTITLE" --stdout --title "Restore Planka" --cancel-label "Back" --menu "Choose a file you want to restore:" 0 0 0 "${files[@]}")
    rc=$?
    clear
    if [ $rc -ne 0 ] || [ -z "$file" ]; then
        dialog_backup
        return
    fi

    # Extract next to the archive; the archive holds one top-level directory
    RESTORE_TMP=$(mktemp -d "$(dirname "$file")/.restore.XXXXXX") || restore_fail "Cannot create a temporary directory."
    echo -n "Extracting tarball $file ... "
    tar -C "$RESTORE_TMP" -xzf "$file" || restore_fail "Extraction failed."
    echo -e "\e[1;32mSuccess!\e[0m"

    entries=$(find "$RESTORE_TMP" -mindepth 1 -maxdepth 1)
    if [ "$(echo "$entries" | wc -l)" -ne 1 ] || [ ! -d "$entries" ]; then
        restore_fail "Invalid backup: expected one top-level directory. Nothing was changed."
    fi
    local dir="$entries"

    if [ ! -f "$dir/postgres.sql" ] || [ ! -d "$dir/data" ]; then
        restore_fail "Invalid backup: postgres.sql and data/ are required (backups from older installer versions are not supported). Nothing was changed."
    fi

    # PostgreSQL refuses to drop a database with open connections and psql carries on after that error
    echo -n "Stopping Planka ... "
    docker stop "$PLANKA_DOCKER_CONTAINER_PLANKA" >/dev/null || restore_fail "Could not stop Planka."
    docker exec "$PLANKA_DOCKER_CONTAINER_POSTGRES" psql -U postgres -Atqc \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE backend_type = 'client backend' AND pid <> pg_backend_pid()" >/dev/null \
        || restore_fail "Could not close the open database connections. Planka is stopped."
    echo -e "\e[1;32mSuccess!\e[0m"

    echo -n "Importing postgres database ... "
    docker exec -i "$PLANKA_DOCKER_CONTAINER_POSTGRES" psql -U postgres < "$dir/postgres.sql" >/dev/null \
        || restore_fail "Database import failed. Planka is stopped."
    echo -e "\e[1;32mSuccess!\e[0m"

    echo -n "Importing data volume ... "
    docker run --rm --user root --volumes-from "$PLANKA_DOCKER_CONTAINER_PLANKA" -v "$dir:/backup" node:24-alpine \
        sh -c "cp -rf /backup/data/. /app/data && chown -R node:node /app/data" \
        || restore_fail "Data import failed. Planka is stopped."
    echo -e "\e[1;32mSuccess!\e[0m"

    echo -n "Starting Planka ... "
    docker start "$PLANKA_DOCKER_CONTAINER_PLANKA" >/dev/null || restore_fail "Could not start Planka."
    echo -e "\e[1;32mSuccess!\e[0m"

    echo -n "Cleaning up temporary files and folders ... "
    rm -rf "$RESTORE_TMP"
    echo -e "\e[1;32mSuccess!\e[0m"

    echo -e "\e[1;32mRestore complete!\e[0m"

    read -p "Do you want to open the installer again? (yes/no) " yn

    case $yn in
        yes) bash /opt/planka_installer.sh ;;
        no) echo "exiting...";
            exit;;
        * ) echo "invalid response";
            exit 1;;
    esac
}


function remove_planka {
    if [ -f "$COMPOSE_FILE" ]; then
        cd "$INSTALL_DIR" || exit 1
        clear
        docker compose down -v
        rm -Rf cron/ logs/ .env docker-compose.yml
        rm -f /etc/nginx/sites-enabled/planka.conf
        rm -f /etc/cron.daily/planka-cron
        systemctl restart nginx
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

# Quote a value for a compose .env file: single quotes, a single quote becomes \'
function env_line {
    local value=${2//\'/\\\'}
    printf "%s='%s'\n" "$1" "$value"
}

# Ask for a required value: re-ask on empty, exit on Cancel
function ask_required {
    local var=$1 text=$2 kind=${3:---inputbox} value rc
    while true; do
        value=$(dialog --backtitle "$MAINTITLE" "$kind" "$text" 15 60 3>&1 1>&2 2>&3 3>&-)
        rc=$?
        [ $rc -ne 0 ] && exit_clear
        [ -n "$value" ] && break
        dialog --backtitle "$MAINTITLE" --title "ERROR" --msgbox "This value is required." 8 40
    done
    printf -v "$var" '%s' "$value"
}

function config {
    mkdir -p "$INSTALL_DIR"/{cron,backup}
    mkdir -p "$INSTALL_DIR"/logs/{app,nginx}
    chmod -R 777 "$INSTALL_DIR"/logs/app

    # Initialize empty advanced config
    ADVANCED_CONFIG=""

    while true; do
        ask_required base_url "Please enter the Domain or Subdomain, you want to use for Planka.      Do NOT enter http:// or https://).     Like planka.example.com"
        [[ "$base_url" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && break
        dialog --backtitle "$MAINTITLE" --title "ERROR" --msgbox "This is not a valid domain name." 8 40
    done
    ask_required email "Please enter a email address for the first admin user"
    ask_required name "Please enter the name of the first admin user"
    ask_required username "Please enter a username for the first admin user"
    ask_required password "Please enter a password for the first admin user" --passwordbox
    secret_key=$(openssl rand -hex 64)

    # Ask if user wants to configure advanced options
    dialog --backtitle "$MAINTITLE" \
    --title "Advanced Configuration" \
    --yesno "Would you like to configure advanced options?" 15 60
    response=$?
    case $response in
        0) config_advanced ;;
    esac
}

function write_config {
    local scheme=http
    [[ "$1" == "https" ]] && scheme=https

    (
        umask 077
        {
            env_line BASE_URL "$scheme://$base_url"
            env_line SECRET_KEY "$secret_key"
            env_line DEFAULT_ADMIN_EMAIL "$email"
            env_line DEFAULT_ADMIN_NAME "$name"
            env_line DEFAULT_ADMIN_USERNAME "$username"
            env_line DEFAULT_ADMIN_PASSWORD "$password"
            printf '%s' "$ADVANCED_CONFIG"
        } > "$CONFIG_FILE"
    )
    chmod 600 "$CONFIG_FILE"
}

# Append KEY='value' to ADVANCED_CONFIG unless the value is empty
function add_advanced {
    [ -n "$2" ] && ADVANCED_CONFIG+="$(env_line "$1" "$2")"$'\n'
}

function config_advanced {
    # Initialize variables with default values
    LOG_LEVEL="warn"
    TOKEN_EXPIRES_IN="365"
    DEFAULT_LANGUAGE="en-US"
    SHOW_DETAILED_AUTH_ERRORS="false"
    ACTIVE_USERS_LIMIT=""

    # SMTP and S3 settings, as ready-made .env lines
    SMTP_CONFIG=""
    S3_CONFIG=""

    while true; do
        CHOICE=$(dialog --clear \
            --backtitle "$MAINTITLE" \
            --title "Advanced Configuration" \
            --menu "Choose an option to configure:" 20 60 12 \
            1 "Log Level" \
            2 "Token Expiration" \
            3 "Default Language" \
            4 "Active Users Limit" \
            5 "Show Detailed Auth Errors" \
            6 "Configure SMTP" \
            7 "Configure S3" \
            8 "Save and Exit" \
            2>&1 >/dev/tty)

        case $CHOICE in
            1)
                LOG_LEVEL=$(dialog --backtitle "$MAINTITLE" \
                    --title "Log Level" \
                    --menu "Select log level:" 15 60 4 \
                    "error" "Error only" \
                    "warn" "Warnings and errors" \
                    "info" "Information level" \
                    "debug" "Debug level" \
                    2>&1 >/dev/tty)
                ;;
            2)
                TOKEN_EXPIRES_IN=$(dialog --backtitle "$MAINTITLE" \
                    --inputbox "Enter token expiration in days:" 15 60 "$TOKEN_EXPIRES_IN" \
                    2>&1 >/dev/tty)
                ;;
            3)
                DEFAULT_LANGUAGE=$(dialog --backtitle "$MAINTITLE" \
                    --inputbox "Enter default language (e.g. en-US, de-DE):" 15 60 "$DEFAULT_LANGUAGE" \
                    2>&1 >/dev/tty)
                ;;
            4)
                ACTIVE_USERS_LIMIT=$(dialog --backtitle "$MAINTITLE" \
                    --inputbox "Enter active users limit (leave empty for unlimited):" 15 60 "$ACTIVE_USERS_LIMIT" \
                    2>&1 >/dev/tty)
                ;;
            5)
                SHOW_DETAILED_AUTH_ERRORS=$(dialog --backtitle "$MAINTITLE" \
                    --menu "Show detailed auth errors?" 15 60 2 \
                    "true" "Yes" \
                    "false" "No" \
                    2>&1 >/dev/tty)
                ;;
            6)
                configure_smtp
                ;;
            7)
                configure_s3
                ;;
            *)
                # Save and Exit, Cancel and Esc
                ADVANCED_CONFIG=""
                add_advanced LOG_LEVEL "$LOG_LEVEL"
                add_advanced TOKEN_EXPIRES_IN "$TOKEN_EXPIRES_IN"
                add_advanced DEFAULT_LANGUAGE "$DEFAULT_LANGUAGE"
                add_advanced ACTIVE_USERS_LIMIT "$ACTIVE_USERS_LIMIT"
                add_advanced SHOW_DETAILED_AUTH_ERRORS "$SHOW_DETAILED_AUTH_ERRORS"
                ADVANCED_CONFIG+="$SMTP_CONFIG$S3_CONFIG"
                return
                ;;
        esac
    done
}

function configure_smtp {
    SMTP_HOST=$(dialog --backtitle "$MAINTITLE" \
        --inputbox "Enter SMTP host:" 15 60 \
        2>&1 >/dev/tty)

    if [ -n "$SMTP_HOST" ]; then
        SMTP_PORT=$(dialog --backtitle "$MAINTITLE" \
            --inputbox "Enter SMTP port:" 15 60 "587" \
            2>&1 >/dev/tty)

        SMTP_SECURE=$(dialog --backtitle "$MAINTITLE" \
            --menu "Use secure connection?" 15 60 2 \
            "true" "Yes" \
            "false" "No" \
            2>&1 >/dev/tty)

        SMTP_USER=$(dialog --backtitle "$MAINTITLE" \
            --inputbox "Enter SMTP username:" 15 60 \
            2>&1 >/dev/tty)

        SMTP_PASSWORD=$(dialog --backtitle "$MAINTITLE" \
            --passwordbox "Enter SMTP password:" 15 60 \
            2>&1 >/dev/tty)

        SMTP_FROM=$(dialog --backtitle "$MAINTITLE" \
            --inputbox "Enter SMTP from address:" 15 60 \
            2>&1 >/dev/tty)

        SMTP_CONFIG="$(env_line SMTP_HOST "$SMTP_HOST")
$(env_line SMTP_PORT "$SMTP_PORT")
$(env_line SMTP_SECURE "$SMTP_SECURE")
$(env_line SMTP_USER "$SMTP_USER")
$(env_line SMTP_PASSWORD "$SMTP_PASSWORD")
$(env_line SMTP_FROM "$SMTP_FROM")
"
    fi
}

function configure_s3 {
    S3_ENDPOINT=$(dialog --backtitle "$MAINTITLE" \
        --inputbox "Enter S3 endpoint:" 15 60 \
        2>&1 >/dev/tty)

    if [ -n "$S3_ENDPOINT" ]; then
        S3_REGION=$(dialog --backtitle "$MAINTITLE" \
            --inputbox "Enter S3 region:" 15 60 \
            2>&1 >/dev/tty)

        S3_ACCESS_KEY_ID=$(dialog --backtitle "$MAINTITLE" \
            --inputbox "Enter S3 access key ID:" 15 60 \
            2>&1 >/dev/tty)

        S3_SECRET_ACCESS_KEY=$(dialog --backtitle "$MAINTITLE" \
            --passwordbox "Enter S3 secret access key:" 15 60 \
            2>&1 >/dev/tty)

        S3_BUCKET=$(dialog --backtitle "$MAINTITLE" \
            --inputbox "Enter S3 bucket name:" 15 60 \
            2>&1 >/dev/tty)

        S3_FORCE_PATH_STYLE=$(dialog --backtitle "$MAINTITLE" \
            --menu "Use force path style?" 15 60 2 \
            "true" "Yes" \
            "false" "No" \
            2>&1 >/dev/tty)

        S3_CONFIG="$(env_line S3_ENDPOINT "$S3_ENDPOINT")
$(env_line S3_REGION "$S3_REGION")
$(env_line S3_ACCESS_KEY_ID "$S3_ACCESS_KEY_ID")
$(env_line S3_SECRET_ACCESS_KEY "$S3_SECRET_ACCESS_KEY")
$(env_line S3_BUCKET "$S3_BUCKET")
$(env_line S3_FORCE_PATH_STYLE "$S3_FORCE_PATH_STYLE")
"
    fi
}

function restart_planka {
    if [ -f "$COMPOSE_FILE" ]; then
        cd "$INSTALL_DIR" || exit 1
        # Keeps the volumes of older installs and still applies .env changes
        docker compose up -d --force-recreate
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
        2 "Admin user settings"
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
        2) dialog_admin_user ;;
        3) dialog_main ;;
        4) exit_clear ;;
    esac
}

# Replace or add KEY in .env; the value can contain any character
function set_env_value {
    local tmp
    tmp=$(mktemp "$INSTALL_DIR/.env.XXXXXX") || return 1
    { grep -v "^$1=" "$CONFIG_FILE" || true; } > "$tmp"
    env_line "$1" "$2" >> "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$CONFIG_FILE"
}

# Ask for a new admin value and store it
function change_admin_value {
    local key=$1 label=$2 kind=$3 value
    value=$(dialog --backtitle "$MAINTITLE" "$kind" "Please enter a new $label" 15 60 3>&1 1>&2 2>&3 3>&-) || return 0
    [ -z "$value" ] && return 0
    if set_env_value "$key" "$value"; then
        dialog --title "Success" --backtitle "$MAINTITLE" --msgbox "The $label was changed. Please restart Planka" 15 60
    else
        dialog --title "ERROR" --backtitle "$MAINTITLE" --msgbox "Could not update $CONFIG_FILE" 15 60
    fi
}

function dialog_admin_user {
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --title "ERROR" --backtitle "$MAINTITLE" --msgbox 'ERROR...Planka is not installed' 15 60
        dialog_config
        return
    fi

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
    case $CONFIG_CHOICE in
        1) change_admin_value DEFAULT_ADMIN_NAME "name" --inputbox; dialog_admin_user ;;
        2) change_admin_value DEFAULT_ADMIN_USERNAME "username" --inputbox; dialog_admin_user ;;
        3) change_admin_value DEFAULT_ADMIN_EMAIL "email address" --inputbox; dialog_admin_user ;;
        4) change_admin_value DEFAULT_ADMIN_PASSWORD "password" --passwordbox; dialog_admin_user ;;
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
        9 "Exit"
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
        7) restart_planka ;;
        8) dialog_remove_planka ;;
        9) exit_clear ;;
    esac
}
#=======================================================================================================================
##################################
#         Program start         #
##################################
export LANG=C.UTF-8

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[0;31mPlease run the installer as root.\e[0m"
    exit 1
fi

# The configuration needs these before install_packages runs
missing=()
command -v dialog >/dev/null || missing+=(dialog)
command -v curl >/dev/null || missing+=(curl)
command -v openssl >/dev/null || missing+=(openssl)
[ -f /etc/ssl/certs/ca-certificates.crt ] || missing+=(ca-certificates)

if [ ${#missing[@]} -gt 0 ]; then
    if ! command -v apt-get >/dev/null; then
        echo -e "\e[0;31mYour OS is not Supported\e[0m"
        exit 1
    fi
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" || exit 1
fi

clear
echo -e "\e[1;100m####   Welcome to the  Planka installer   ####\e[0m"
sleep 2
dialog_main

#=======================================================================================================================
