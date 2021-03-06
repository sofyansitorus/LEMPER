#!/bin/bash

_REPO_BASE_URL="https://raw.githubusercontent.com/sofyansitorus/LEMPER/master"
_COMMON_PACKAGES=(software-properties-common dialog apt-utils gcc g++ make curl wget git zip unzip openssl perl)
_PHP_VERSIONS=(5.6 7.0 7.1 7.2 7.3 7.4)
_PHP_EXTENSIONS=(cli gd mysql curl zip xdebug)
_SITE_PRESETS=(php wordpress)
_OPTIONS_YES_NO=(yes no)

_DB_NAME=""
_DB_USER=""
_DB_PASSWORD=""

_lemper_install() {
    __print_header "Starting the install procedure"
    __print_divider

    __check_os ${@}

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

_lemper_purge() {
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

    local _SUDO=$(__parse_args sudo ${@})

    while [[ -z "$_SUDO" ]]; do
        echo -e "Do you want to add user to sudo group? "

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _SUDO=$_ITEM
            break
        done
    done

    local _CRYPTED_PASS=$(perl -e 'print crypt($ARGV[0], "password")' $_PASSWORD)

    useradd -m -s /bin/bash -p $_CRYPTED_PASS $_USERNAME >/dev/null

    if [ $? -ne 0 ]; then
        echo -e "Failed to add a user!"
        exit 1
    fi

    if [ "$_SUDO" = "yes" ]; then
        sudo usermod -aG sudo ${_USERNAME}
    fi

    echo -e "User $_USERNAME has been added!"

    local _USER_CONF_DIR="/etc/nginx/lemper.io/conf/users"
    local _USER_CONF_FILE="${_USER_CONF_DIR}/${_USERNAME}"

    if [ ! -d "${_USER_CONF_DIR}" ]; then
        sudo mkdir -p "${_USER_CONF_DIR}"
    fi

    if [ -f "./nginx/lemper.io/templates/conf/users.conf" ]; then
        sudo cp "./nginx/lemper.io/templates/conf/users.conf" "${_USER_CONF_FILE}"
    elif [ -f "/etc/nginx/lemper.io/templates/conf/users.conf" ]; then
        sudo cp "/etc/nginx/lemper.io/templates/conf/users.conf" "${_USER_CONF_FILE}"
    else
        sudo wget -O "/etc/nginx/lemper.io/templates/conf/users.conf" "${_REPO_BASE_URL}/nginx/lemper.io/templates/conf/users.conf"
        sudo cp "/etc/nginx/lemper.io/templates/conf/users.conf" "${_USER_CONF_FILE}"
    fi

    sed -i -e "s/{{USERNAME}}/${_USERNAME}/g" "${_USER_CONF_FILE}"
    sed -i -e "s/{{PASSWORD}}/${_CRYPTED_PASS}/g" "${_USER_CONF_FILE}"
    sed -i -e "s/{{SUDO}}/${_SUDO}/g" "${_USER_CONF_FILE}"

    __print_divider

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
        _php_pool_generate "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"
        _php_fastcgi_generate "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"
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

    local _SITES=$(__get_existing_sites $_USERNAME)

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

    local _USER_CONF_DIR="/etc/nginx/lemper.io/conf/users"
    local _USER_CONF_FILE="${_USER_CONF_DIR}/${_USERNAME}"

    if [ -f "${_USER_CONF_FILE}" ]; then
        sudo rm -rf "${_USER_CONF_FILE}"
    fi

    echo -e "User $_USERNAME has been deleted from system!"

    __print_divider
}

_user_update() {
    __print_header "Update existing user"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user to update: "

        select _ITEM in ${_USERS[@]}; do
            _USERNAME=$_ITEM
            break
        done
    done

    local _CHANGE_PASSWORD=$(__parse_args change_password ${@})

    while [[ -z "$_CHANGE_PASSWORD" ]]; do
        echo -e "Do you want to change user password? "

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _CHANGE_PASSWORD=$_ITEM
            break
        done
    done

    local _PASSWORD=$(__parse_args password ${@})

    if [ "${_CHANGE_PASSWORD}" = "yes" ]; then
        while [[ -z "$_PASSWORD" ]]; do
            echo -n "Enter new password: "
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
    fi

    local _CHANGE_SUDO=$(__parse_args change_sudo ${@})

    while [[ -z "$_CHANGE_SUDO" ]]; do
        echo -e "Do you want to change user sudo group? "

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _CHANGE_SUDO=$_ITEM
            break
        done
    done

    local _SUDO=$(__parse_args sudo ${@})

    if [ "${_CHANGE_SUDO}" = "yes" ]; then
        while [[ -z "$_SUDO" ]]; do
            echo -e "Do you want to add user to sudo group? "

            select _ITEM in ${_OPTIONS_YES_NO[@]}; do
                _SUDO=$_ITEM
                break
            done
        done
    fi

    local _REGENERATE_PHP_POOL=$(__parse_args regenerate_php_pool ${@})

    while [[ -z "$_REGENERATE_PHP_POOL" ]]; do
        echo -e "Do you want to re-generate PHP Pool? "

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _REGENERATE_PHP_POOL=$_ITEM
            break
        done
    done

    local _REGENERATE_PHP_FASTCGI=$(__parse_args regenerate_php_fastcgi ${@})

    while [[ -z "$_REGENERATE_PHP_FASTCGI" ]]; do
        echo -e "Do you want to re-generate PHP FastCGI? "

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _REGENERATE_PHP_FASTCGI=$_ITEM
            break
        done
    done

    local _USER_CONF_DIR="/etc/nginx/lemper.io/conf/users"
    local _USER_CONF_FILE="${_USER_CONF_DIR}/${_USERNAME}"

    if [ "${_CHANGE_PASSWORD}" = "yes" ]; then
        local _CRYPTED_PASS=$(perl -e 'print crypt($ARGV[0], "password")' $_PASSWORD)

        usermod -p $_CRYPTED_PASS $_USERNAME >/dev/null

        if [ -f "${_USER_CONF_FILE}" ]; then
            sed -i -e "s/password\=.*/password\=${_CRYPTED_PASS}/" "${_USER_CONF_FILE}"
        fi
    fi

    if [ "${_CHANGE_SUDO}" = "yes" ]; then
        if [ "${_SUDO}" = "yes" ]; then
            sudo usermod -aG sudo ${_USERNAME}
        else
            sudo deluser ${_USERNAME} sudo
        fi

        if [ -f "${_USER_CONF_FILE}" ]; then
            sed -i -e "s/sudo\=.*/sudo\=${_SUDO}/" "${_USER_CONF_FILE}"
        fi
    fi

    if [ "$_REGENERATE_PHP_POOL" = "yes" ] || [ "$_REGENERATE_PHP_FASTCGI" = "yes" ]; then
        for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
            if [ "$_REGENERATE_PHP_POOL" = "yes" ]; then
                _php_pool_generate "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"
            fi

            if [ "$_REGENERATE_PHP_FASTCGI" = "yes" ]; then
                _php_fastcgi_generate "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"
            fi

            sudo service "php${_PHP_VERSION}-fpm" restart
        done
    fi

    echo -e "User $_USERNAME has been updated!"

    __print_divider
}

_php_pool_generate() {
    __print_header "Generating PHP-FPM pool file"

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

    if [ -f "./nginx/lemper.io/templates/php_pool.conf" ]; then
        sudo cp "./nginx/lemper.io/templates/php_pool.conf" "${_CONF_FILE}"
    elif [ -f "/etc/nginx/lemper.io/templates/php_pool.conf" ]; then
        sudo cp "/etc/nginx/lemper.io/templates/php_pool.conf" "${_CONF_FILE}"
    else
        sudo wget -O "/etc/nginx/lemper.io/templates/php_pool.conf" "${_REPO_BASE_URL}/nginx/lemper.io/templates/php_pool.conf"
        sudo cp "/etc/nginx/lemper.io/templates/php_pool.conf" "${_CONF_FILE}"
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
    __print_header "Deleting PHP-FPM pool file"

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

_php_fastcgi_generate() {
    __print_header "Generating PHP-FastCGI configuration file"

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

    if [ -f "./nginx/lemper.io/templates/php_fastcgi.conf" ]; then
        sudo cp "./nginx/lemper.io/templates/php_fastcgi.conf" "${_CONF_FILE}"
    elif [ -f "/etc/nginx/lemper.io/templates/php_fastcgi.conf" ]; then
        sudo cp "/etc/nginx/lemper.io/templates/php_fastcgi.conf" "${_CONF_FILE}"
    else
        sudo wget -O "/etc/nginx/lemper.io/templates/php_fastcgi.conf" "${_REPO_BASE_URL}/nginx/lemper.io/templates/php_fastcgi.conf"
        sudo cp "/etc/nginx/lemper.io/templates/php_fastcgi.conf" "${_CONF_FILE}"
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
        _database_create "--username=${_USERNAME}" ${@}
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

    # start creating site procedure
    local _CONF_SITE_AVAILABLE="/etc/nginx/sites-available/${_USERNAME}_${_DOMAIN}.conf"
    local _CONF_SITE_ENABLED="/etc/nginx/sites-enabled/${_USERNAME}_${_DOMAIN}.conf"

    if [ -f "./nginx/lemper.io/presets/${_SITE_PRESET}.conf" ]; then
        sudo cp "./nginx/lemper.io/presets/${_SITE_PRESET}.conf" "${_CONF_SITE_AVAILABLE}"
    elif [ -f "/etc/nginx/lemper.io/presets/${_SITE_PRESET}.conf" ]; then
        sudo cp "/etc/nginx/lemper.io/presets/${_SITE_PRESET}.conf" "${_CONF_SITE_AVAILABLE}"
    else
        sudo wget -O "/etc/nginx/lemper.io/presets/${_SITE_PRESET}.conf" "${_REPO_BASE_URL}/nginx/lemper.io/presets/${_SITE_PRESET}.conf"
        sudo cp "/etc/nginx/lemper.io/presets/${_SITE_PRESET}.conf" "${_CONF_SITE_AVAILABLE}"
    fi

    sed -i -e "s/{{USERNAME}}/${_USERNAME}/g" "${_CONF_SITE_AVAILABLE}"
    sed -i -e "s/{{PHP_VERSION}}/${_PHP_VERSION}/g" "${_CONF_SITE_AVAILABLE}"
    sed -i -e "s/{{DOMAIN}}/${_DOMAIN}/g" "${_CONF_SITE_AVAILABLE}"
    sed -i -e "s/{{EXTRA_DOMAINS}}/${_EXTRA_DOMAINS}/g" "${_CONF_SITE_AVAILABLE}"

    sudo ln -s "${_CONF_SITE_AVAILABLE}" "${_CONF_SITE_ENABLED}"

    sudo nginx -t && sudo systemctl reload nginx

    local _WWW_ROOT_DIR="/home/${_USERNAME}/www"
    local _SITE_ROOT_DIR="${_WWW_ROOT_DIR}/${_DOMAIN}"
    local _SITE_PUBLIC_DIR="${_SITE_ROOT_DIR}/public"
    local _SITE_LETSENCRYPT_DIR="${_SITE_ROOT_DIR}/.letsencrypt"

    if [ ! -d "${_WWW_ROOT_DIR}" ]; then
        sudo mkdir -p "${_WWW_ROOT_DIR}"
        sudo chown -R "${_USERNAME}:${_USERNAME}" "${_WWW_ROOT_DIR}"
    fi

    if [ ! -d "${_SITE_ROOT_DIR}" ]; then
        sudo mkdir -p "${_SITE_ROOT_DIR}"
        sudo chown -R "${_USERNAME}:${_USERNAME}" "${_SITE_ROOT_DIR}"
    fi

    if [ ! -d "${_SITE_PUBLIC_DIR}" ]; then
        sudo mkdir -p "${_SITE_PUBLIC_DIR}"
        sudo chown -R "${_USERNAME}:${_USERNAME}" "${_SITE_PUBLIC_DIR}"
    fi

    if [ -d "${_SITE_PUBLIC_DIR}" ]; then
        if [ -f "./nginx/lemper.io/templates/lemper.io.html" ]; then
            sudo cp "./nginx/lemper.io/templates/lemper.io.html" "${_SITE_PUBLIC_DIR}/lemper.io.html"
        elif [ -f "/etc/nginx/lemper.io/templates/lemper.io.html" ]; then
            sudo cp "/etc/nginx/lemper.io/templates/lemper.io.html" "${_SITE_PUBLIC_DIR}/lemper.io.html"
        else
            sudo wget -O "/etc/nginx/lemper.io/templates/lemper.io.html" "${_REPO_BASE_URL}/nginx/lemper.io/templates/lemper.io.html"
            sudo cp "/etc/nginx/lemper.io/templates/lemper.io.html" "${_SITE_PUBLIC_DIR}/lemper.io.html"
        fi

        if [ -f "${_SITE_PUBLIC_DIR}/lemper.io.html" ]; then
            sed -i -e "s/{{DOMAIN}}/${_DOMAIN}/g" "${_SITE_PUBLIC_DIR}/lemper.io.html"
            sudo chown -R "${_USERNAME}:${_USERNAME}" "${_SITE_PUBLIC_DIR}/lemper.io.html"
        fi
    fi

    if [ "$_ENABLE_SSL" = "yes" ]; then
        sudo mkdir -p "${_SITE_LETSENCRYPT_DIR}"

        if [ -d "${_SITE_LETSENCRYPT_DIR}" ]; then
            sudo chown -R "${_USERNAME}:${_USERNAME}" "${_SITE_LETSENCRYPT_DIR}"

            sudo openssl dhparam -out /etc/nginx/dhparam.pem 2048
            sudo nginx -t && sudo systemctl reload nginx

            sudo certbot certonly --webroot -d ${_DOMAIN} --email ${_ADMIN_EMAIL} -w ${_SITE_LETSENCRYPT_DIR} -n --agree-tos --force-renewal
            sed -i -r 's/#?;#//g' "${_CONF_SITE_AVAILABLE}"
            sudo nginx -t && sudo systemctl reload nginx

            if [ ! -f /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh ]; then
                echo -e '#!/bin/bash\nnginx -t && systemctl reload nginx' | sudo tee /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
            fi

            if [ -f /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh ]; then
                sudo chmod a+x /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
            fi
        fi
    fi

    local _SITE_CONF_DIR="/etc/nginx/lemper.io/conf/sites/${_USERNAME}"
    local _SITE_CONF_FILE="${_SITE_CONF_DIR}/${_DOMAIN}"

    if [ ! -d "${_SITE_CONF_DIR}" ]; then
        sudo mkdir -p "${_SITE_CONF_DIR}"
    fi

    if [ -f "./nginx/lemper.io/templates/conf/sites.conf" ]; then
        sudo cp "./nginx/lemper.io/templates/conf/sites.conf" "${_SITE_CONF_FILE}"
    elif [ -f "/etc/nginx/lemper.io/templates/conf/sites.conf" ]; then
        sudo cp "/etc/nginx/lemper.io/templates/conf/sites.conf" "${_SITE_CONF_FILE}"
    else
        sudo wget -O "/etc/nginx/lemper.io/templates/conf/sites.conf" "${_REPO_BASE_URL}/nginx/lemper.io/templates/conf/sites.conf"
        sudo cp "/etc/nginx/lemper.io/templates/conf/sites.conf" "${_SITE_CONF_FILE}"
    fi

    sed -i -e "s/{{USERNAME}}/${_USERNAME}/g" "${_SITE_CONF_FILE}"
    sed -i -e "s/{{DOMAIN}}/${_DOMAIN}/g" "${_SITE_CONF_FILE}"
    sed -i -e "s/{{EXTRA_DOMAINS}}/${_EXTRA_DOMAINS}/g" "${_SITE_CONF_FILE}"
    sed -i -e "s/{{PHP_VERSION}}/${_PHP_VERSION}/g" "${_SITE_CONF_FILE}"
    sed -i -e "s/{{SITE_PRESET}}/${_SITE_PRESET}/g" "${_SITE_CONF_FILE}"
    sed -i -e "s/{{CREATE_DATABASE}}/${_CREATE_DATABASE}/g" "${_SITE_CONF_FILE}"
    sed -i -e "s/{{ENABLE_SSL}}/${_ENABLE_SSL}/g" "${_SITE_CONF_FILE}"

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

    local _SITES=$(__get_existing_sites $_USERNAME)

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

    local _CONF_SITE_AVAILABLE="/etc/nginx/sites-available/${_USERNAME}_${_DOMAIN}.conf"

    if [ -f "${_CONF_SITE_AVAILABLE}" ]; then
        sudo rm -rf "${_CONF_SITE_AVAILABLE}"

        if [ "$_RESTART_SERVICE" != "no" ]; then
            sudo nginx -t && sudo systemctl reload nginx
        fi
    fi

    local _SITE_CONF_DIR="/etc/nginx/lemper.io/conf/sites/${_USERNAME}"
    local _SITE_CONF_FILE="${_SITE_CONF_DIR}/${_DOMAIN}"

    if [ -f "${_SITE_CONF_FILE}" ]; then
        sudo rm -rf "${_SITE_CONF_FILE}"
    fi

    if [ "$_DELETE_FILES"="yes" ]; then
        local _SITE_ROOT_DIR="/home/${_USERNAME}/www/${_DOMAIN}"

        if [ -d "${_SITE_ROOT_DIR}" ]; then
            sudo rm -rf "${_SITE_ROOT_DIR}"
        fi
    fi

    echo -e "Site ${_DOMAIN} has been deleted"

    __print_divider
}

_database_create() {
    __print_header "Creating database"

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

    _DB_NAME=$(__parse_args db_name ${@})

    while [[ -z "$_DB_NAME" ]]; do
        echo -n "Enter MySQL database name: "
        stty -echo

        #read
        local _CHARCOUNT=0
        local _PROMPT="${_USERNAME}_"

        while IFS= read -p "$_PROMPT" -r -s -n 1 ch; do
            # Enter - accept
            if [[ $ch == $'\0' ]]; then
                break
            fi

            # Backspace
            if [[ $ch == $'\177' ]]; then
                if [ $_CHARCOUNT -gt 0 ]; then
                    _CHARCOUNT=$((_CHARCOUNT - 1))
                    _PROMPT=$'\b \b'
                    _DB_NAME="${_DB_NAME%?}"
                else
                    _PROMPT=''
                fi
            else
                _CHARCOUNT=$((_CHARCOUNT + 1))
                _PROMPT="$ch"
                _DB_NAME+="$ch"
            fi
        done

        stty echo

        echo
    done

    _DB_NAME="${_USERNAME}_${_DB_NAME}"

    _DB_USER=$(__parse_args db_user ${@})

    while [[ -z "$_DB_USER" ]]; do
        echo -n "Enter MySQL database username: "
        stty -echo

        #read
        local _CHARCOUNT=0
        local _PROMPT="${_USERNAME}_"

        while IFS= read -p "$_PROMPT" -r -s -n 1 ch; do
            # Enter - accept
            if [[ $ch == $'\0' ]]; then
                break
            fi

            # Backspace
            if [[ $ch == $'\177' ]]; then
                if [ $_CHARCOUNT -gt 0 ]; then
                    _CHARCOUNT=$((_CHARCOUNT - 1))
                    _PROMPT=$'\b \b'
                    _DB_USER="${_DB_USER%?}"
                else
                    _PROMPT=''
                fi
            else
                _CHARCOUNT=$((_CHARCOUNT + 1))
                _PROMPT="$ch"
                _DB_USER+="$ch"
            fi
        done

        stty echo

        echo
    done

    _DB_USER="${_USERNAME}_${_DB_USER}"

    _DB_PASSWORD=$(__parse_args db_password ${@})

    while [[ -z "$_DB_PASSWORD" ]]; do
        echo -n "Enter MySQL database password: "
        stty -echo

        #read
        local _CHARCOUNT=0
        local _PROMPT=''

        while IFS= read -p "$_PROMPT" -r -s -n 1 ch; do
            # Enter - accept
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

    local _MYSQL_ROOT_PASSWORD=$(__parse_args mysql_root_password ${@})

    while [[ -z "$_MYSQL_ROOT_PASSWORD" ]]; do
        echo -n "Enter MySQL Root Password: [root]"
        stty -echo

        #read
        local _CHARCOUNT=0
        local _PROMPT=''

        while IFS= read -p "$_PROMPT" -r -s -n 1 ch; do
            # Enter - accept
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

    local _SQL_CREATE_DATABASE="CREATE DATABASE ${_DB_NAME};"
    local _SQL_CREATE_USER="CREATE USER '${_DB_USER}'@'%' IDENTIFIED BY '${_DB_PASSWORD}';"
    local _SQL_GRANT="GRANT ALL PRIVILEGES ON ${_DB_NAME}.* TO '${_DB_USER}'@'%';"
    local _SQL_FLUSH="FLUSH PRIVILEGES;"

    echo $_SQL_CREATE_DATABASE
    echo $_SQL_CREATE_USER
    echo $_SQL_GRANT
    echo $_SQL_FLUSH

    # mysql -u root -p${_MYSQL_ROOT_PASSWORD} -e "${_SQL_CREATE_DATABASE}${_SQL_CREATE_USER}${_SQL_GRANT}${_SQL_FLUSH}"

    local _DATABASE_CONF_DIR="/etc/nginx/lemper.io/conf/databases/${_USERNAME}"
    local _DATABASE_CONF_FILE="${_DATABASE_CONF_DIR}/${_DOMAIN}"

    if [ ! -d "${_DATABASE_CONF_DIR}" ]; then
        sudo mkdir -p "${_DATABASE_CONF_DIR}"
    fi

    if [ -f "./nginx/lemper.io/templates/conf/databases.conf" ]; then
        sudo cp "./nginx/lemper.io/templates/conf/databases.conf" "${_DATABASE_CONF_FILE}"
    elif [ -f "/etc/nginx/lemper.io/templates/conf/databases.conf" ]; then
        sudo cp "/etc/nginx/lemper.io/templates/conf/databases.conf" "${_DATABASE_CONF_FILE}"
    else
        sudo wget -O "/etc/nginx/lemper.io/templates/conf/databases.conf" "${_REPO_BASE_URL}/nginx/lemper.io/templates/conf/databases.conf"
        sudo cp "/etc/nginx/lemper.io/templates/conf/databases.conf" "${_DATABASE_CONF_FILE}"
    fi

    sed -i -e "s/{{USERNAME}}/${_USERNAME}/g" "${_DATABASE_CONF_FILE}"
    sed -i -e "s/{{DOMAIN}}/${_DOMAIN}/g" "${_DATABASE_CONF_FILE}"
    sed -i -e "s/{{EXTRA_DOMAINS}}/${_EXTRA_DOMAINS}/g" "${_DATABASE_CONF_FILE}"
    sed -i -e "s/{{PHP_VERSION}}/${_PHP_VERSION}/g" "${_DATABASE_CONF_FILE}"
    sed -i -e "s/{{SITE_PRESET}}/${_SITE_PRESET}/g" "${_DATABASE_CONF_FILE}"
    sed -i -e "s/{{CREATE_DATABASE}}/${_CREATE_DATABASE}/g" "${_DATABASE_CONF_FILE}"
    sed -i -e "s/{{ENABLE_SSL}}/${_ENABLE_SSL}/g" "${_DATABASE_CONF_FILE}"
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

    local _BASE_DIR="/etc/nginx/lemper.io/fastcgi/${_USERNAME}"

    if [ ! -d "${_BASE_DIR}" ]; then
        sudo mkdir -p "${_BASE_DIR}"
    fi

    echo "${_BASE_DIR}/php${_PHP_VERSION}.conf"
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

    local _BASE_DIR="/var/run/lemper.io/${_USERNAME}"

    if [ ! -d "${_BASE_DIR}" ]; then
        sudo mkdir -p "${_BASE_DIR}"
    fi

    echo "${_BASE_DIR}/php${_PHP_VERSION}-fpm.sock"
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
    local _CHAR=$2
    if [ -z "$_CHAR" ]; then
        _CHAR="+"
    fi

    __print_divider "${_CHAR}"
    echo -e ">>> $1"
    __print_divider "${_CHAR}"
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

__install_common() {
    __print_header "Installing common packages"

    for _COMMON_PACKAGE in ${_COMMON_PACKAGES[@]}; do
        sudo apt-get -y --no-upgrade install ${_COMMON_PACKAGE}
    done

    __print_divider
}

__install_nginx() {
    __purge_apache

    __print_header "Installing NGINX"

    sudo apt-get -y --no-upgrade install nginx

    echo ""

    local _BACKUP_FILE=nginx.conf_$(date +'%F_%H-%M-%S')
    local _BACKUP_DIR_DEST="/etc/nginx/lemper.io/backup"
    local _BACKUP_FILE_DEST="${_BACKUP_DIR_DEST}/${_BACKUP_FILE}"

    if [ ! -d "${_BACKUP_DIR_DEST}" ]; then
        echo -e "Creating backup directory: ${_BACKUP_DIR_DEST}"
        sudo mkdir -p "${_BACKUP_DIR_DEST}"
    fi

    echo -e "Creating backup for existing configuration file: /etc/nginx/nginx.conf >>> ${_BACKUP_FILE_DEST}"

    sudo cp /etc/nginx/nginx.conf ${_BACKUP_FILE_DEST}

    echo -e "Overriding configuration file : /etc/nginx/nginx.conf"

    if [ -f "./nginx/nginx.conf" ]; then
        sudo cp "./nginx/nginx.conf" "/etc/nginx/nginx.conf"
    else
        sudo wget -O "/etc/nginx/nginx.conf" "${_REPO_BASE_URL}/nginx/nginx.conf"
    fi

    echo ""

    local _INCLUDE_FILES=(general.conf security.conf wordpress.conf)

    for _INCLUDE_FILE in ${_INCLUDE_FILES[@]}; do
        local _INCLUDE_DIR_DEST="/etc/nginx/lemper.io/includes"
        local _INCLUDE_FILE_DEST="${_INCLUDE_DIR_DEST}/${_INCLUDE_FILE}"

        if [ ! -d "${_INCLUDE_DIR_DEST}" ]; then
            echo -e "Creating include directory: ${_INCLUDE_DIR_DEST}"
            sudo mkdir -p "${_INCLUDE_DIR_DEST}"
        fi

        echo -e "Creating include file : ${_INCLUDE_FILE_DEST}"

        if [ -f "./nginx/lemper.io/includes/$_INCLUDE_FILE" ]; then
            sudo cp "./nginx/lemper.io/includes/$_INCLUDE_FILE" "${_INCLUDE_FILE_DEST}"
        else
            sudo wget -O "${_INCLUDE_FILE_DEST}" "${_REPO_BASE_URL}/nginx/lemper.io/includes/$_INCLUDE_FILE"
        fi
    done

    echo ""

    local _PRESET_FILES=(php.conf wordpress.conf)

    for _PRESET_FILE in ${_PRESET_FILES[@]}; do
        local _PRESET_DIR_DEST="/etc/nginx/lemper.io/presets"
        local _PRESET_FILE_DEST="${_PRESET_DIR_DEST}/${_PRESET_FILE}"

        if [ ! -d "${_PRESET_DIR_DEST}" ]; then
            echo -e "Creating preset directory: ${_PRESET_DIR_DEST}"
            sudo mkdir -p "${_PRESET_DIR_DEST}"
        fi

        echo -e "Creating preset file : ${_PRESET_FILE_DEST}"

        if [ -f "./nginx/lemper.io/presets/$_PRESET_FILE" ]; then
            sudo cp "./nginx/lemper.io/presets/$_PRESET_FILE" "${_PRESET_FILE_DEST}"
        else
            sudo wget -O "${_PRESET_FILE_DEST}" "${_REPO_BASE_URL}/nginx/lemper.io/presets/$_PRESET_FILE"
        fi
    done

    echo ""

    local _TEMPLATE_FILES=(php_fastcgi.conf php_pool.conf lemper.io.html)

    for _TEMPLATE_FILE in ${_TEMPLATE_FILES[@]}; do
        local _TEMPLATE_DIR_DEST="/etc/nginx/lemper.io/templates"
        local _TEMPLATE_FILE_DEST="${_TEMPLATE_DIR_DEST}/${_TEMPLATE_FILE}"

        if [ ! -d "${_TEMPLATE_DIR_DEST}" ]; then
            echo -e "Creating template directory: ${_TEMPLATE_DIR_DEST}"
            sudo mkdir -p "${_TEMPLATE_DIR_DEST}"
        fi

        echo -e "Creating template file : ${_TEMPLATE_FILE_DEST}"

        if [ -f "./nginx/lemper.io/templates/$_TEMPLATE_FILE" ]; then
            sudo cp "./nginx/lemper.io/templates/$_TEMPLATE_FILE" "${_TEMPLATE_FILE_DEST}"
        else
            sudo wget -O "${_TEMPLATE_FILE_DEST}" "${_REPO_BASE_URL}/nginx/lemper.io/templates/$_TEMPLATE_FILE"
        fi
    done

    local _CONF_FILES=(sites.conf users.conf databases.conf)

    for _CONF_FILE in ${_CONF_FILES[@]}; do
        local _CONF_DIR_DEST="/etc/nginx/lemper.io/templates/conf"
        local _CONF_FILE_DEST="${_CONF_DIR_DEST}/${_CONF_FILE}"

        if [ ! -d "${_CONF_DIR_DEST}" ]; then
            echo -e "Creating template directory: ${_CONF_DIR_DEST}"
            sudo mkdir -p "${_CONF_DIR_DEST}"
        fi

        echo -e "Creating template file : ${_CONF_FILE_DEST}"

        if [ -f "./nginx/lemper.io/templates/conf/$_CONF_FILE" ]; then
            sudo cp "./nginx/lemper.io/templates/conf/$_CONF_FILE" "${_CONF_FILE_DEST}"
        else
            sudo wget -O "${_CONF_FILE_DEST}" "${_REPO_BASE_URL}/nginx/lemper.io/templates/conf/$_CONF_FILE"
        fi
    done

    __print_divider

    nginx -v

    __print_divider
}

__install_certbot() {
    __print_header "Installing Certbot"

    sudo apt-get -y install software-properties-common

    sudo add-apt-repository -y universe
    sudo add-apt-repository -y ppa:certbot/certbot

    sudo apt-get -y --no-upgrade update
    sudo apt-get -y --no-upgrade install certbot

    __print_divider

    certbot --version

    __print_divider
}

__install_mariadb() {
    __print_header "Installing MySQL server"

    if ! which mysql >/dev/null 2>&1; then
        local _MYSQL_ROOT_PASSWORD=$(__parse_args mysql_root_password ${@})

        while [[ -z "$_MYSQL_ROOT_PASSWORD" ]]; do
            echo -n "Enter MySQL Root Password:"

            stty -echo

            #read
            local _CHARCOUNT=0
            local _PROMPT=''

            while IFS= read -p "$_PROMPT" -r -s -n 1 ch; do
                # Enter - accept
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
        done

        export DEBIAN_FRONTEND=noninteractive

        echo "mariadb-server mysql-server/root_password password $_MYSQL_ROOT_PASSWORD" | sudo debconf-set-selections
        echo "mariadb-server mysql-server/root_password_again password $_MYSQL_ROOT_PASSWORD" | sudo debconf-set-selections

        sudo apt-get -y --no-upgrade install mariadb-server

        local _SQL_USE="use mysql;"
        local _SQL_UPDATE_USER="UPDATE user SET authentication_string=PASSWORD('$_MYSQL_ROOT_PASSWORD'), plugin='' WHERE user='root';"
        local _SQL_FLUSH="FLUSH PRIVILEGES;"

        mysql -u root "-p${_MYSQL_ROOT_PASSWORD}" -e "${_SQL_USE}${_SQL_UPDATE_USER}${_SQL_FLUSH}"
    fi

    __print_divider

    $(which mysql) --version

    __print_divider
}

__install_php() {
    __print_header "Installing PHP"

    sudo apt-get -y --no-upgrade install software-properties-common
    sudo add-apt-repository -y ppa:ondrej/php
    sudo add-apt-repository -y ppa:ondrej/nginx
    sudo apt-get -y update

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
        __print_header "Installing PHP version: ${_PHP_VERSION}"

        sudo apt-get -y --no-upgrade install "php${_PHP_VERSION}-fpm"

        for _PHP_EXTENSION in ${_PHP_EXTENSIONS[@]}; do
            __print_header "Installing PHP extension: php${_PHP_VERSION}-${_PHP_EXTENSION}" "-"

            sudo apt-get -y --no-upgrade install "php${_PHP_VERSION}-${_PHP_EXTENSION}"
        done

        __print_divider
    done
}

__install_composer() {
    __print_header "Installing Composer"

    sudo apt-get -y --no-upgrade install composer

    __print_divider

    which composer

    __print_divider
}

__install_wp_cli() {
    __print_header "Installing WP-CLI"

    if ! which wp >/dev/null 2>&1; then
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        sudo mv wp-cli.phar /usr/local/bin/wp

        __print_divider
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

    nodejs --version

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

    yarn --version

    __print_divider
}

__purge_nginx() {
    __print_header "Purging NGINX"

    sudo apt-get -y purge nginx*

    sudo rm -rf /etc/nginx/lemper.io
    sudo rm -rf /var/run/lemper.io

    __print_divider
}

__purge_apache() {
    __print_header "Purging Apache"

    sudo apt-get -y purge apache\*

    __print_divider
}

__purge_mariadb() {
    __print_header "Purging MySQL"

    sudo apt-get -y purge mariadb*

    sudo rm -rf /etc/mariadb

    __print_divider
}

__purge_php() {
    __print_header "Purging PHP"

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
        sudo service "php${_PHP_VERSION}-fpm" stop

        sudo apt-get -y --purge remove "php${_PHP_VERSION}-fpm"

        sudo rm -rf "/etc/php/${_PHP_VERSION}"
    done

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

__is_sudo_user() {
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
    echo $(find "/etc/nginx/lemper.io/conf/users" -type f -exec basename {} \;)
}

__get_existing_sites() {
    echo $(find "/etc/nginx/lemper.io/conf/sites/${1}" -type f -exec basename {} \;)
}

# Execute the main command
__main() {
    if [ $(__is_sudo_user) -ne 0 ]; then
        echo "Only root and sudoer users allowed to execute this script!"
        exit 1
    fi

    if [ ! -d "/etc/nginx/lemper.io" ]; then
        echo "It is appear that you did not install the LEMPER.IO yet. Would you like to install it now ?"

        local _INSTALL_NOW=""

        select _ITEM in ${_OPTIONS_YES_NO[@]}; do
            _INSTALL_NOW=$_ITEM
            break
        done

        if [ "${_INSTALL_NOW}" != "yes" ]; then
            echo "Goodbye!"
            exit 1
        fi

        _lemper_install ${@:2}
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
