#!/bin/bash

_REPO_BASE_URL="https://raw.githubusercontent.com/sofyansitorus/LEMPER/master"
_CWD=$(pwd)
_APT_REPOSITORIES=(universe ppa:ondrej/php ppa:certbot/certbot)
_COMMON_PACKAGES=(software-properties-common dialog apt-utils gcc g++ make curl wget git zip unzip openssl perl)
_PHP_VERSIONS=(5.6 7.0 7.1 7.2 7.3 7.4)
_PHP_EXTENSIONS=(cli fpm gd mysql curl zip xdebug)
_SITE_PRESETS=(php wordpress)
_OPTIONS_YES_NO=(yes no)
_OPTIONS_NO_YES=(no yes)

_DB_NAME=""
_DB_USER=""
_DB_PASSWORD=""
_DB_HOST=""

_install() {
    __print_header "Starting the install procedure"
    __print_divider

    __check_os ${@}

    __add_ppa ${@}

    __install_common ${@}
    __install_nginx ${@}
    __install_certbot ${@}
    __install_mariadb ${@}
    __install_php ${@}
    __install_composer ${@}
    __install_wp_cli ${@}
    __install_nodejs ${@}
    __install_yarn ${@}

    __cleaning_up ${@}
}

_purge() {
    __print_header "Starting the purge procedure"
    __print_divider

    __check_os ${@}

    __purge_yarn ${@}
    __purge_nodejs ${@}
    __purge_wp_cli ${@}
    __purge_composer ${@}
    __purge_php ${@}
    __purge_mariadb ${@}
    __purge_nginx ${@}

    __cleaning_up ${@}
}

_user_add() {
    __print_header "Adding new user"

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter username: " _USERNAME
    done

    egrep "^$_USERNAME" /etc/passwd >/dev/null

    while [ $? -eq 0 ]; do
        echo -e "User $_USERNAME already exists"
        read -p "Enter username: " _USERNAME
        egrep "^$_USERNAME" /etc/passwd >/dev/null
    done

    local _PASSWORD=$(__parse_args password ${@})

    while [[ -z "$_PASSWORD" ]]; do
        echo -n "Enter password: "
        stty -echo

        #read password
        local _CHARCOUNT=0
        local _PROMPT=''

        while IFS= read -p "$_PROMPT" -r -s -n 1 ch; do
            # Enter - accept password
            if [[ $ch == $'\0' ]]; then
                break
            fi

            # Backspace
            if [[ $ch == $'\177' ]]; then
                if [ $_CHARCOUNT -gt 0 ]; then
                    _CHARCOUNT=$((_CHARCOUNT - 1))
                    _PROMPT=$'\b \b'
                    _PASSWORD="${_PASSWORD%?}"
                else
                    _PROMPT=''
                fi
            else
                _CHARCOUNT=$((_CHARCOUNT + 1))
                _PROMPT='*'
                _PASSWORD+="$ch"
            fi
        done

        stty echo

        echo
    done

    local _CRYPTED_PASS=$(perl -e 'print crypt($ARGV[0], "password")' $_PASSWORD)

    local _SUDO=$(__parse_args sudo ${@})

    while [[ -z "$_SUDO" ]]; do
        echo -e "Do you want to add user to sudo group? "

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _SUDO=$_ITEM
            break
        done
    done

    useradd -m -p $_CRYPTED_PASS $_USERNAME >/dev/null

    if [ $? -ne 0 ]; then
        echo -e "Failed to add a user!"
        exit 1
    fi

    if [ "$_SUDO" = "yes" ]; then
        sudo usermod -aG sudo ${_USERNAME}
    fi

    echo -e "User $_USERNAME has been added to system!"

    __print_divider

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
        _php_pool_add "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"
        _php_fastcgi_add "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"
        sudo service "php${_PHP_VERSION}-fpm" restart
    done
}

_user_delete() {
    __print_header "Deleting existing user"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user to delete: "

        select _ITEM in ${_USERS[@]}; do
            _USERNAME=$_ITEM
            break
        done
    done

    if [ $(__is_valid_user "$_USERNAME") -ne 0 ]; then
        echo "User $_USERNAME is invalid!"
        exit 1
    fi

    if [ "$_USERNAME" = "$USER" ]; then
        echo "You are not allowed to delete your own account!"
        exit 1
    fi

    local _DELETE_FILES=$(__parse_args delete_files ${@})

    while [[ -z "$_DELETE_FILES" ]]; do
        echo -e "Do you want to delete user files ?"

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _DELETE_FILES=$_ITEM
            break
        done
    done

    local _SITES=$(__get_user_sites $_USERNAME)

    if [ -n "$_SITES" ]; then
        for _DOMAIN in ${_SITES[@]}; do
            _site_delete "--username=${_USERNAME}" "--domain=${_DOMAIN}" "--delete_files=${_DELETE_FILES}" "--restart_service=no"
        done

        sudo nginx -t && sudo systemctl reload nginx
    fi

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
        _php_pool_delete "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"
        _php_fastcgi_delete "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"

        sudo service "php${_PHP_VERSION}-fpm" restart
    done

    __print_header "Deleting existing user"

    if [ "${_DELETE_FILES}" = "yes" ]; then
        userdel -r "$_USERNAME"
    else
        userdel "$_USERNAME"
    fi

    echo -e "User $_USERNAME has been deleted from system!"

    __print_divider
}

_php_pool_add() {
    __print_header "Adding PHP-FPM pool"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user: "

        select _ITEM in ${_USERS[@]}; do
            _USERNAME=$_ITEM
            break
        done
    done

    if [ $(__is_valid_user "$_USERNAME") -ne 0 ]; then
        echo "User $_USERNAME is invalid!"
        exit 1
    fi

    local _PHP_VERSION=$(__parse_args php_version ${@})

    if [ -z "$_PHP_VERSION" ]; then
        echo -e "Select the PHP version configuration: [7.2]"

        select _ITEM in ${_PHP_VERSIONS[@]}; do
            _PHP_VERSION=$_ITEM
            break
        done

        _PHP_VERSION=${_PHP_VERSION:-"7.2"}
    fi

    local _CONF_FILE=$(__php_pool_conf_file "--username=${_USERNAME}" "--php_version=${_PHP_VERSION}" ${@})
    local _SOCK_FILE=$(__php_fastcgi_sock_file "--username=${_USERNAME}" "--php_version=${_PHP_VERSION}" ${@})

    echo "Copying file ${_CONF_FILE}"

    if [ -f "./template/php_pool.conf" ]; then
        sudo cp "./template/php_pool.conf" "${_CONF_FILE}"
    else
        sudo wget -O "${_CONF_FILE}" "${_REPO_BASE_URL}/template/php_pool.conf"
    fi

    sed -i -e "s#{{USERNAME}}#${_USERNAME}#g" "${_CONF_FILE}"
    sed -i -e "s#{{SOCK_FILE}}#${_SOCK_FILE}#g" "${_CONF_FILE}"

    local _RESTART_SERVICE=$(__parse_args restart_service ${@})

    if [ "$_RESTART_SERVICE" != "no" ]; then
        sudo service "php${_PHP_VERSION}-fpm" restart
    fi

    __print_divider
}

_php_pool_delete() {
    __print_header "Deleting PHP-FPM pool"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user: "

        select _ITEM in ${_USERS[@]}; do
            _USERNAME=$_ITEM
            break
        done
    done

    if [ $(__is_valid_user "$_USERNAME") -ne 0 ]; then
        echo "User $_USERNAME is invalid!"
        exit 1
    fi

    local _PHP_VERSION=$(__parse_args php_version ${@})

    if [ -z "$_PHP_VERSION" ]; then
        echo -e "Select the PHP version configuration: [7.2]"

        select _ITEM in ${_PHP_VERSIONS[@]}; do
            _PHP_VERSION=$_ITEM
            break
        done

        _PHP_VERSION=${_PHP_VERSION:-"7.2"}
    fi

    local _CONF_FILE=$(__php_pool_conf_file "--username=${_USERNAME}" "--php_version=${_PHP_VERSION}" ${@})

    if [ -f "$_CONF_FILE" ]; then
        echo "Deleting file ${_CONF_FILE}"

        sudo rm -rf "${_CONF_FILE}"
    fi

    local _RESTART_SERVICE=$(__parse_args restart_service ${@})

    if [ "$_RESTART_SERVICE" != "no" ]; then
        sudo service "php${_PHP_VERSION}-fpm" restart
    fi

    __print_divider
}

_php_fastcgi_add() {
    __print_header "Adding PHP-FastCGI configuration file"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user: "

        select _ITEM in ${_USERS[@]}; do
            _USERNAME=$_ITEM
            break
        done
    done

    if [ $(__is_valid_user "$_USERNAME") -ne 0 ]; then
        echo "User $_USERNAME is invalid!"
        exit 1
    fi

    local _PHP_VERSION=$(__parse_args php_version ${@})

    if [ -z "$_PHP_VERSION" ]; then
        echo -e "Select the PHP version configuration: [7.2]"

        select _ITEM in ${_PHP_VERSIONS[@]}; do
            _PHP_VERSION=$_ITEM
            break
        done

        _PHP_VERSION=${_PHP_VERSION:-"7.2"}
    fi

    local _CONF_FILE=$(__php_fastcgi_conf_file "--username=${_USERNAME}" "--php_version=${_PHP_VERSION}" ${@})
    local _SOCK_FILE=$(__php_fastcgi_sock_file "--username=${_USERNAME}" "--php_version=${_PHP_VERSION}" ${@})

    echo "Copying file ${_CONF_FILE}"

    if [ -f "./template/php_fastcgi.conf" ]; then
        sudo cp -p "./template/php_fastcgi.conf" "${_CONF_FILE}"
    else
        sudo wget -O "${_CONF_FILE}" "${_REPO_BASE_URL}/template/php_fastcgi.conf"
    fi

    sed -i -e "s#{{SOCK_FILE}}#${_SOCK_FILE}#g" "${_CONF_FILE}"

    local _RESTART_SERVICE=$(__parse_args restart_service ${@})

    if [ "$_RESTART_SERVICE" != "no" ]; then
        sudo service "php${_PHP_VERSION}-fpm" restart
    fi

    __print_divider
}

_php_fastcgi_delete() {
    __print_header "Deleting PHP-FastCGI configuration file"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user: "

        select _ITEM in ${_USERS[@]}; do
            _USERNAME=$_ITEM
            break
        done
    done

    if [ $(__is_valid_user "$_USERNAME") -ne 0 ]; then
        echo "User $_USERNAME is invalid!"
        exit 1
    fi

    local _PHP_VERSION=$(__parse_args php_version ${@})

    if [ -z "$_PHP_VERSION" ]; then
        echo -e "Select the PHP version configuration: [7.2]"

        select _ITEM in ${_PHP_VERSIONS[@]}; do
            _PHP_VERSION=$_ITEM
            break
        done

        _PHP_VERSION=${_PHP_VERSION:-"7.2"}
    fi

    local _CONF_FILE=$(__php_fastcgi_conf_file "--username=${_USERNAME}" "--php_version=${_PHP_VERSION}" ${@})

    if [ -f "$_CONF_FILE" ]; then
        echo "Deleting file ${_CONF_FILE}"

        sudo rm -rf "${_CONF_FILE}"
    fi

    local _RESTART_SERVICE=$(__parse_args restart_service ${@})

    if [ "$_RESTART_SERVICE" != "no" ]; then
        sudo service "php${_PHP_VERSION}-fpm" restart
    fi

    __print_divider
}

_site_add() {
    __print_header "Adding new site"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user: "

        select _ITEM in ${_USERS[@]}; do
            _USERNAME=$_ITEM
            break
        done
    done

    if [ $(__is_valid_user "$_USERNAME") -ne 0 ]; then
        echo "User $_USERNAME is invalid!"
        exit 1
    fi

    local _DOMAIN=$(__parse_args domain ${@})

    while [[ -z "$_DOMAIN" ]]; do
        read -p "Enter domain: " _DOMAIN
    done

    local _EXTRA_DOMAINS=$(__parse_args extra_domains ${@})

    if [ -z "$_EXTRA_DOMAINS" ]; then
        read -p "Enter extra domains (Separate witch space for multiple domains): " _EXTRA_DOMAINS
    fi

    local _PHP_VERSION=$(__parse_args php_version ${@})

    if [ -z "$_PHP_VERSION" ]; then
        echo -e "Select the PHP version configuration: [7.2]"

        select _ITEM in ${_PHP_VERSIONS[@]}; do
            _PHP_VERSION=$_ITEM
            break
        done

        _PHP_VERSION=${_PHP_VERSION:-"7.2"}
    fi

    local _SITE_PRESET=$(__parse_args site_preset ${@})

    if [ -z "$_SITE_PRESET" ]; then
        echo -e "Select site configuration preset: [php] "

        select _ITEM in ${_SITE_PRESETS[@]}; do
            _SITE_PRESET=$_ITEM
            break
        done

        _SITE_PRESET=${_SITE_PRESET:-"php"}
    fi

    local _CREATE_DATABASE=$(__parse_args create_database ${@})

    while [[ -z "$_CREATE_DATABASE" ]]; do
        echo -e "Do you want to create database? "

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _CREATE_DATABASE=$_ITEM
            break
        done
    done

    if [ "$_CREATE_DATABASE" = "yes" ]; then
        _database_add "--username=${_USERNAME}" ${@}
    fi

    local _ENABLE_SSL=$(__parse_args enable_ssl ${@})

    while [[ -z "$_ENABLE_SSL" ]]; do
        echo -e "Do you want to enable SSL? "

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _ENABLE_SSL=$_ITEM
            break
        done
    done

    _ADMIN_EMAIL=$(__parse_args admin_email ${@})

    if [ "$_ENABLE_SSL" = "yes" ]; then
        while [[ -z "$_ADMIN_EMAIL" ]]; do
            read -p "Enter email address for the site administrator: [info@${_DOMAIN}] " _ADMIN_EMAIL
            _ADMIN_EMAIL=${_ADMIN_EMAIL:-"info@${_DOMAIN}"}
        done
    fi

    echo "_USERNAME=$_USERNAME"
    echo "_DOMAIN=$_DOMAIN"
    echo "_EXTRA_DOMAINS=$_EXTRA_DOMAINS"
    echo "_PHP_VERSION=$_PHP_VERSION"
    echo "_SITE_PRESET=$_SITE_PRESET"
    echo "_CREATE_DATABASE=$_CREATE_DATABASE"
    echo "_DB_NAME=$_DB_NAME"
    echo "_DB_USER=$_DB_USER"
    echo "_DB_PASSWORD=$_DB_PASSWORD"
    echo "_DB_HOST=$_DB_HOST"
    echo "_ENABLE_SSL=$_ENABLE_SSL"
    echo "_ADMIN_EMAIL=$_ADMIN_EMAIL"

    # start creating site procedure
    local _CONF_SITE_AVAILABLE="/etc/nginx/sites-available/${_USERNAME}_${_DOMAIN}.conf"
    local _CONF_SITE_ENABLED="/etc/nginx/sites-enabled/${_USERNAME}_${_DOMAIN}.conf"

    if [ -f "./template/preset/${_SITE_PRESET}.conf" ]; then
        sudo cp "./template/preset/${_SITE_PRESET}.conf" "${_CONF_SITE_AVAILABLE}"
    else
        sudo wget -O "${_CONF_SITE_AVAILABLE}" "${_REPO_BASE_URL}/template/preset/${_SITE_PRESET}.conf"
    fi

    sed -i -e "s/{{USERNAME}}/${_USERNAME}/g" "${_CONF_SITE_AVAILABLE}"
    sed -i -e "s/{{PHP_VERSION}}/${_PHP_VERSION}/g" "${_CONF_SITE_AVAILABLE}"
    sed -i -e "s/{{DOMAIN}}/${_DOMAIN}/g" "${_CONF_SITE_AVAILABLE}"
    sed -i -e "s/{{EXTRA_DOMAINS}}/${_EXTRA_DOMAINS}/g" "${_CONF_SITE_AVAILABLE}"

    sudo ln -s "${_CONF_SITE_AVAILABLE}" "${_CONF_SITE_ENABLED}"

    sudo nginx -t && sudo systemctl reload nginx

    local _WWW_ROOT="/home/${_USERNAME}/www"
    local _SITE_ROOT="${_WWW_ROOT}/${_DOMAIN}"
    local _LETSENCRYPT_ROOT="${_SITE_ROOT}/.letsencrypt"

    sudo mkdir -p "${_SITE_ROOT}/public"
    sudo chown -R "${_USERNAME}:${_USERNAME}" "${_WWW_ROOT}"

    if [ "$_ENABLE_SSL" = "yes" ]; then
        sudo mkdir -p "${_LETSENCRYPT_ROOT}"
        sudo chown -R "${_USERNAME}:${_USERNAME}" "${_LETSENCRYPT_ROOT}"

        sudo openssl dhparam -out /etc/nginx/dhparam.pem 2048
        sudo nginx -t && sudo systemctl reload nginx

        sudo certbot certonly --webroot -d ${_DOMAIN} --email ${_ADMIN_EMAIL} -w ${_LETSENCRYPT_ROOT} -n --agree-tos --force-renewal
        sed -i -r 's/#?;#//g' "${_CONF_SITE_AVAILABLE}"
        sudo nginx -t && sudo systemctl reload nginx

        if [ ! -f /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh ]; then
            echo -e '#!/bin/bash\nnginx -t && systemctl reload nginx' | sudo tee /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
        fi

        if [ -f /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh ]; then
            sudo chmod a+x /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
        fi
    fi

    __print_divider
}

_site_delete() {
    __print_header "Deleting existing site"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user: "

        select _ITEM in ${_USERS[@]}; do
            _USERNAME=$_ITEM
            break
        done
    done

    if [ $(__is_valid_user "$_USERNAME") -ne 0 ]; then
        echo "User $_USERNAME is invalid!"
        exit 1
    fi

    local _SITES=$(__get_user_sites $_USERNAME)

    if [ -z "$_SITES" ]; then
        echo "No sites available for selected user. Please add new using the 'site_add' command!"
        exit 1
    fi

    local _DOMAIN=$(__parse_args domain ${@})

    while [[ -z "$_DOMAIN" ]]; do
        echo -e "Domain to delete: "

        select _ITEM in ${_SITES[@]}; do
            _DOMAIN=${_ITEM}
            break
        done
    done

    local _DELETE_FILES=$(__parse_args delete_files ${@})

    while [[ -z "$_DELETE_FILES" ]]; do
        echo -e "Do you want to delete site files ?"

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _DELETE_FILES=$_ITEM
            break
        done
    done

    local _RESTART_SERVICE=$(__parse_args restart_service ${@})

    local _CONF_SITE_ENABLED="/etc/nginx/sites-enabled/${_USERNAME}_${_DOMAIN}.conf"

    if [ -f "${_CONF_SITE_ENABLED}" ]; then
        sudo rm -rf "${_CONF_SITE_ENABLED}"

        if [ "$_RESTART_SERVICE" != "no" ]; then
            sudo nginx -t && sudo systemctl reload nginx
        fi
    fi

    local _CONF_SITE_AVAILABLE="/etc/nginx/sites-available/${_USERNAME}_${_DOMAIN}.conf"

    if [ -f "${_CONF_SITE_AVAILABLE}" ]; then
        sudo rm -rf "${_CONF_SITE_AVAILABLE}"

        if [ "$_RESTART_SERVICE" != "no" ]; then
            sudo nginx -t && sudo systemctl reload nginx
        fi
    fi

    if [ "$_DELETE_FILES"="yes" ]; then
        local _SITE_ROOT="/home/${_USERNAME}/www/${_DOMAIN}"

        if [ -d "${_SITE_ROOT}" ]; then
            sudo rm -rf "${_SITE_ROOT}"
        fi
    fi

    echo -e "Site ${_DOMAIN} has been deleted"

    __print_divider
}

_database_add() {
    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter system user that will be used as database prefix: [$USER] " _USERNAME
        _USERNAME=${_USERNAME:-$USER}
    done

    egrep "^$_USERNAME" /etc/passwd >/dev/null

    if [ $? -ne 0 ]; then
        echo "User $_USERNAME not exists!"
        exit 1
    fi

    _DB_NAME=$(__parse_args db_name ${@})

    while [[ -z "$_DB_NAME" ]]; do
        read -p "Enter MySQL database name: " _DB_NAME
    done

    _DB_USER=$(__parse_args db_user ${@})

    while [[ -z "$_DB_USER" ]]; do
        read -p "Enter MySQL database username: " _DB_USER
    done

    _DB_PASSWORD=$(__parse_args db_password ${@})

    while [[ -z "$_DB_PASSWORD" ]]; do
        echo -n "Enter MySQL database password: "
        stty -echo

        #read password
        local _CHARCOUNT=0
        local _PROMPT=''

        while IFS= read -p "$_PROMPT" -r -s -n 1 ch; do
            # Enter - accept password
            if [[ $ch == $'\0' ]]; then
                break
            fi

            # Backspace
            if [[ $ch == $'\177' ]]; then
                if [ $_CHARCOUNT -gt 0 ]; then
                    _CHARCOUNT=$((_CHARCOUNT - 1))
                    _PROMPT=$'\b \b'
                    _DB_PASSWORD="${_DB_PASSWORD%?}"
                else
                    _PROMPT=''
                fi
            else
                _CHARCOUNT=$((_CHARCOUNT + 1))
                _PROMPT='*'
                _DB_PASSWORD+="$ch"
            fi
        done

        stty echo

        echo
    done

    _DB_HOST=$(__parse_args db_host ${@})

    while [[ -z "$_DB_HOST" ]]; do
        read -p "Enter MySQL hostname: [%]" _DB_HOST
        _DB_HOST=${_DB_HOST:-"%"}
    done

    local _MYSQL_ROOT_PASSWORD=$(__parse_args mysql_root_password ${@})

    while [[ -z "$_MYSQL_ROOT_PASSWORD" ]]; do
        echo -n "Enter MySQL Root Password: [root]"
        stty -echo

        #read password
        local _CHARCOUNT=0
        local _PROMPT=''

        while IFS= read -p "$_PROMPT" -r -s -n 1 ch; do
            # Enter - accept password
            if [[ $ch == $'\0' ]]; then
                break
            fi

            # Backspace
            if [[ $ch == $'\177' ]]; then
                if [ $_CHARCOUNT -gt 0 ]; then
                    _CHARCOUNT=$((_CHARCOUNT - 1))
                    _PROMPT=$'\b \b'
                    _MYSQL_ROOT_PASSWORD="${_MYSQL_ROOT_PASSWORD%?}"
                else
                    _PROMPT=''
                fi
            else
                _CHARCOUNT=$((_CHARCOUNT + 1))
                _PROMPT='*'
                _MYSQL_ROOT_PASSWORD+="$ch"
            fi
        done

        stty echo

        echo

        _MYSQL_ROOT_PASSWORD=${_MYSQL_ROOT_PASSWORD:-"root"}
    done

    local _SQL_CREATE_DATABASE="CREATE DATABASE IF NOT EXISTS ${_USERNAME}_${_DB_NAME};"
    local _SQL_CREATE_USER="CREATE USER IF NOT EXISTS '${_USERNAME}_${_DB_USER}'@'${_DB_HOST}' IDENTIFIED BY '${_DB_PASSWORD}';"
    local _SQL_GRANT="GRANT ALL PRIVILEGES ON ${_USERNAME}_${_DB_NAME}.* TO '${_USERNAME}_${_DB_USER}'@'${_DB_HOST}';"
    local _SQL_FLUSH="FLUSH PRIVILEGES;"

    mysql -u root -p${_MYSQL_ROOT_PASSWORD} -e "${_SQL_CREATE_DATABASE}${_SQL_CREATE_USER}${_SQL_GRANT}${_SQL_FLUSH}"
}

__php_pool_conf_file() {
    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter Username: " _USERNAME
    done

    local _PHP_VERSION=$(__parse_args php_version ${@})

    while [[ -z "$_PHP_VERSION" ]]; do
        read -p "Enter PHP Version: " _PHP_VERSION
    done

    echo "/etc/php/${_PHP_VERSION}/fpm/pool.d/${_USERNAME}.conf"
}

__php_fastcgi_conf_file() {
    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter Username: " _USERNAME
    done

    local _PHP_VERSION=$(__parse_args php_version ${@})

    while [[ -z "$_PHP_VERSION" ]]; do
        read -p "Enter PHP Version: " _PHP_VERSION
    done

    echo "/etc/nginx/nginxconfig.io/${_USERNAME}_php${_PHP_VERSION}_fastcgi.conf"
}

__php_fastcgi_sock_file() {
    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter Username: " _USERNAME
    done

    local _PHP_VERSION=$(__parse_args php_version ${@})

    while [[ -z "$_PHP_VERSION" ]]; do
        read -p "Enter PHP Version: " _PHP_VERSION
    done

    echo "/var/run/${_USERNAME}-php${_PHP_VERSION}-fpm.sock"
}

__check_os() {
    __print_header "Checking operating system requirements"

    if ! grep -q 'debian' /etc/os-release; then
        echo "Script only supported for Debian operating system family"
        exit 1
    fi

    cat /etc/os-release

    __print_divider
}

__parse_args() {
    local _MATCH=""

    for _ARGUMENT in ${@:2}; do
        local _KEY=$(echo $_ARGUMENT | cut -f1 -d=)
        local _VALUE=$(echo $_ARGUMENT | cut -f2 -d=)

        if [ "--$1" = "$_KEY" ]; then
            _MATCH=$_VALUE
        fi
    done

    echo "${_MATCH}"
}

__print_header() {
    __print_divider "+"
    echo -e ">>> $1"
    __print_divider "+"
}

__print_divider() {
    local _CHAR=$1

    if [ -z "$_CHAR" ]; then
        _CHAR="="
    fi

    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' ${_CHAR}
}

__cleaning_up() {
    __print_header "Cleaning up"

    sudo apt-get -y autoremove

    __print_divider
}

__add_ppa() {
    local _NEED_UPDATE=0

    for _APT_REPOSITORIY in ${_APT_REPOSITORIES[@]}; do
        grep -h "^deb.*$_APT_REPOSITORIY" /etc/apt/sources.list.d/* >/dev/null 2>&1

        if [ $? -ne 0 ]; then
            __print_header "Adding PPA $_APT_REPOSITORIY"

            sudo add-apt-repository -y $_APT_REPOSITORIY

            __print_divider

            _NEED_UPDATE=1
        fi
    done

    if [ "$_NEED_UPDATE" = "1" ]; then
        __print_header "Updating package lists"

        sudo apt-get -y update

        __print_divider
    fi
}

__install_common() {
    __print_header "Installing common packages"

    local _INSTALL_PACKAGES=""

    for _COMMON_PACKAGE in ${_COMMON_PACKAGES[@]}; do
        _INSTALL_PACKAGES+=" ${_COMMON_PACKAGE}"
    done

    sudo apt-get -y --no-upgrade install ${_INSTALL_PACKAGES}

    __print_divider
}

__install_nginx() {
    sudo dpkg --get-selections | grep -v deinstall | grep "nginx" >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        __purge_apache
    fi

    __print_header "Installing NGINX"

    sudo apt-get -y --no-upgrade install nginx

    if [ ! -d "/etc/nginx/nginxconfig.io" ]; then
        sudo mkdir -p "/etc/nginx/nginxconfig.io"
    fi

    local _CONF_FILES=(nginx.conf nginxconfig.io/general.conf nginxconfig.io/security.conf nginxconfig.io/wordpress.conf)

    local _CONF_FILES_BACKUP=""

    for _CONF_FILE_BACKUP in ${_CONF_FILES[@]}; do
        if [ -f "/etc/nginx/$_CONF_FILE_BACKUP" ]; then
            _CONF_FILES_BACKUP+=" ${_CONF_FILE_BACKUP}"
        fi
    done

    if [ -n "$_CONF_FILES_BACKUP" ]; then
        cd /etc/nginx
        echo -e "Creating backup for existing confguration files:$_CONF_FILES_BACKUP"
        sudo tar -zcvf backup_nginx_$(date +'%F_%H-%M-%S').tar.gz $_CONF_FILES_BACKUP >/dev/null
        cd $_CWD
    fi

    for _CONF_FILE in ${_CONF_FILES[@]}; do
        if [ -f "./nginx/$_CONF_FILE" ]; then
            sudo cp "./nginx/$_CONF_FILE" "/etc/nginx/${_CONF_FILE}"
        else
            sudo wget -O "/etc/nginx/${_CONF_FILE}" "${_REPO_BASE_URL}/nginx/$_CONF_FILE"
        fi
    done

    __print_divider
}

__install_certbot() {
    __print_header "Installing Certbot"

    sudo apt-get -y --no-upgrade install certbot

    __print_divider
}

__install_apache() {
    __print_header "Installing Apache"

    sudo apt-get -y --no-upgrade install apache2

    __print_divider
}

__install_mariadb() {
    __print_header "Installing MariaDB server"

    if ! which mariadb >/dev/null 2>&1; then
        local _MYSQL_ROOT_PASSWORD=$(__parse_args mysql_root_password ${@})

        while [[ -z "$_MYSQL_ROOT_PASSWORD" ]]; do
            echo -n "Enter MySQL Root Password: [root]"
            stty -echo

            #read password
            local _CHARCOUNT=0
            local _PROMPT=''

            while IFS= read -p "$_PROMPT" -r -s -n 1 ch; do
                # Enter - accept password
                if [[ $ch == $'\0' ]]; then
                    break
                fi

                # Backspace
                if [[ $ch == $'\177' ]]; then
                    if [ $_CHARCOUNT -gt 0 ]; then
                        _CHARCOUNT=$((_CHARCOUNT - 1))
                        _PROMPT=$'\b \b'
                        _MYSQL_ROOT_PASSWORD="${_MYSQL_ROOT_PASSWORD%?}"
                    else
                        _PROMPT=''
                    fi
                else
                    _CHARCOUNT=$((_CHARCOUNT + 1))
                    _PROMPT='*'
                    _MYSQL_ROOT_PASSWORD+="$ch"
                fi
            done

            stty echo

            echo

            _MYSQL_ROOT_PASSWORD=${_MYSQL_ROOT_PASSWORD:-"root"}
        done

        #set password from provided arg
        sudo debconf-set-selections <<<"mariadb-server mysql-server/root_password password $_MYSQL_ROOT_PASSWORD"
        sudo debconf-set-selections <<<"mariadb-server mysql-server/root_password_again password $_MYSQL_ROOT_PASSWORD"
    fi

    sudo apt-get -y install --no-upgrade mariadb-server

    __print_divider
}

__install_php() {
    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do

        for _PHP_EXTENSION in ${_PHP_EXTENSIONS[@]}; do
            __print_header "Installing PHP extension: php${_PHP_VERSION}-${_PHP_EXTENSION}"

            sudo apt-get -y --no-upgrade install "php${_PHP_VERSION}-${_PHP_EXTENSION}"

            __print_divider
        done
    done
}

__install_composer() {
    __print_header "Installing Composer"

    sudo apt-get -y --no-upgrade install composer

    __print_divider
}

__install_wp_cli() {
    __print_header "Installing WP-CLI"

    if ! which wp >/dev/null 2>&1; then
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        sudo mv wp-cli.phar /usr/local/bin/wp
    fi

    wp --info --allow-root

    __print_divider
}

__install_nodejs() {
    __print_header "Installing NodeJS"

    if ! which nodejs >/dev/null 2>&1; then
        curl -sL https://deb.nodesource.com/setup_12.x | -E bash -
    fi

    sudo apt-get -y --no-upgrade install nodejs

    __print_divider
}

__install_yarn() {
    __print_header "Installing Yarn"

    echo -e "Installing Yarn"

    if [ ! -f "/etc/apt/sources.list.d/yarn.list" ]; then
        curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -

        echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

        sudo apt-get -y update
    fi

    sudo apt-get -y --no-upgrade install yarn

    __print_divider
}

__purge_nginx() {
    __print_header "Purging NGINX"

    sudo apt-get -y purge nginx*

    __print_divider

    __install_apache
}

__purge_apache() {
    __print_header "Purging Apache"

    sudo apt-get -y purge apache\*

    __print_divider
}

__purge_mariadb() {
    __print_header "Purging MariaDB"

    sudo apt-get -y purge mariadb*

    __print_divider
}

__purge_php() {
    __print_header "Purging PHP"

    sudo apt-get -y --purge remove php-common

    __print_divider
}

__purge_composer() {
    __print_header "Purging Composer"

    sudo apt-get -y purge composer

    __print_divider
}

__purge_wp_cli() {
    __print_header "Purging WP-CLI"

    wp --info --allow-root

    rm -rf /usr/local/bin/wp

    __print_divider
}

__purge_nodejs() {
    __print_header "Purging NodeJS"

    sudo apt-get -y purge nodejs

    __print_divider
}

__purge_yarn() {
    __print_header "Purging Yarn"

    sudo apt-get -y purge yarn

    __print_divider
}

__is_sudoer() {
    if [ $(id -u) -eq 0 ]; then
        echo 0
        exit 0
    fi

    local _SUDOERS=$(__get_sudoers)

    if [ -n "${_SUDOERS}" ]; then
        for _SUDOER in ${_SUDOERS[@]}; do
            if [ "$_SUDOER" = "$USER" ]; then
                echo 0
                exit 0
            fi
        done
    fi

    echo 1
    exit 1
}

__is_valid_user() {
    local _USERS=$(__get_existing_users)

    if [ -n "${_USERS}" ]; then
        for _USER in ${_USERS[@]}; do
            if [ "$_USER" == "$1" ]; then
                echo 0
                exit 0
            fi
        done
    fi

    echo 1
    exit 1
}

__get_sudoers() {
    echo $(grep '^sudo:.*$' /etc/group | cut -d: -f4)
}

__get_existing_users() {
    echo $(awk -F ':' '$3>=1000 && $3<=60000 {print $1}' /etc/passwd)
}

__get_user_sites() {
    echo $(find /etc/nginx/sites-available/ -type f -name "${1}_*" -exec basename {} .conf \; | sed "s/${1}_//g")
}

# Execute the main command
__main() {
    if [ $(__is_sudoer) -ne 0 ]; then
        echo "Only root and sudoer users allowed to execute this script!"
        exit 1
    fi

    _CALLBACK=$(echo ${1} | sed 's/^_\+\(.*\)$/\1/')

    while [[ -z "$_CALLBACK" ]]; do
        echo -e "Select action you want to execute"

        local _CALLBACKS=$(typeset -f | awk '/ \(\) $/ && !/^__/ {print $1}' | sed 's/^_\+\(.*\)$/\1/')

        select _ITEM in ${_CALLBACKS[@]}; do
            _CALLBACK=${_ITEM}
            break
        done
    done

    declare -f -F "_$_CALLBACK" >/dev/null

    if [ $? -ne 0 ]; then
        echo "Function _$_CALLBACK does not exist!"
        exit 1
    fi

    eval "_$_CALLBACK" ${@:2}
}

__main $@
