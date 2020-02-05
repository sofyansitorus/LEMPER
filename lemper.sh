#!/bin/bash

_PWD=$(pwd)
_REPO_BASE_URL="https://raw.githubusercontent.com/sofyansitorus/LEMPER/master"
_COMMON_PACKAGES=(software-properties-common dialog apt-utils gcc g++ make curl wget git zip unzip openssl perl build-essential tcl)
_PHP_VERSIONS=(5.6 7.0 7.1 7.2 7.3 7.4)
_PHP_EXTENSIONS=(common cli gd mysql curl zip xdebug redis)
_SITE_PRESETS=(php wordpress)
_OPTIONS_YES_NO=(yes no)
_OPTIONS_NO_YES=(no yes)
_PROMPT_RESPONSE=""
_COLUMNS=$COLUMNS

_DB_NAME=""
_DB_USER=""
_DB_PASSWORD=""

# Actions
__action_user_add() {
    __print_header "Adding new user"

    local _USERNAME=$(__parse_args username ${@})

    while [ -z "$_USERNAME" ]; do
        read -p "Enter username: " _USERNAME

        if [ -n "$_USERNAME" ]; then
            if [[ "$_USERNAME" =~ [^0-9A-Za-z]+ ]]; then
                __print_error "Username can only contain alphanumeric characters (letters A-Z, numbers 0-9)."
                _USERNAME=""
            else
                egrep "^$_USERNAME" /etc/passwd >/dev/null

                if [ $? -eq 0 ]; then
                    __print_error "User $_USERNAME already exists"
                    _USERNAME=""
                fi
            fi
        fi
    done

    local _PASSWORD=$(__parse_args password ${@})

    if [ -z "${_PASSWORD}" ]; then
        __prompt_password
        _PASSWORD=$_PROMPT_RESPONSE
    fi

    local _CRYPTED_PASS=$(perl -e 'print crypt($ARGV[0], "password")' $_PASSWORD)

    __prompt_no_yes "--prompt_response=$(__parse_args sudo ${@})" "--prompt_label=Do you want to add user to sudo group?"
    _SUDO=$_PROMPT_RESPONSE

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
        __generate_user_php_pool "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"
        __generate_user_php_fastcgi "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}" "--restart_service=no"

        sudo service "php${_PHP_VERSION}-fpm" restart
    done
}

__generate_user_php_pool() {
    __print_header "Generating PHP-FPM pool file"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user: "

        local COLUMNS=0

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

        local COLUMNS=0

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

__generate_user_php_fastcgi() {
    __print_header "Generating PHP-FastCGI configuration file"

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        echo -e "Select user: "

        local COLUMNS=0

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

        local COLUMNS=0

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

# Install
__pre_install() {
    __check_os ${@}

    sudo apt-get -y update

    for _COMMON_PACKAGE in ${_COMMON_PACKAGES[@]}; do
        sudo apt-get -y install ${_COMMON_PACKAGE}
    done
}

__post_install() {
    __print_header "Executing post install scripts"

    sudo apt-get -y autoremove

    __print_divider
}

__install() {
    __print_header "Starting the install procedure"
    __print_divider

    local _COMPONENTS=$(typeset -f | awk '/^__install_/ {print $1}' | sed 's/^__install_\+\(.*\)$/\1/')

    local _COMPONENT=$(__parse_args component ${@})

    if [ ! -d "/etc/nginx/lemper.io" ]; then
        _COMPONENT="all"
    else
        while [[ -z "$_COMPONENT" ]]; do
            echo -e "Select component you want to install: "

            COLUMNS=0

            select _ITEM in ${_COMPONENTS[@]}; do
                _COMPONENT=${_ITEM}
                break
            done

            COLUMNS=$_COLUMNS
        done
    fi

    declare -f -F "__install_$_COMPONENT" >/dev/null

    if [ $? -ne 0 ]; then
        echo "Component $_COMPONENT does not exist!"
        exit 1
    fi

    eval "__install_$_COMPONENT" ${@}
}

__install_all() {
    __pre_install

    __install_nginx ${@}
    __install_certbot ${@}
    __install_mysql ${@}
    __install_redis ${@}
    __install_memcached ${@}
    __install_php ${@}
    __install_composer ${@}
    __install_wp_cli ${@}
    __install_nodejs "--version=12" ${@}
    __install_yarn "--version=stable" ${@}

    __post_install
}

__install_nginx() {
    __print_header "Purging Apache"

    sudo apt-get -y purge apache\*

    __print_divider

    __print_header "Installing NGINX"

    sudo apt-get -y install nginx

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

    if ! which certbot >/dev/null 2>&1; then
        sudo apt-get -y install software-properties-common

        sudo add-apt-repository -y universe
        sudo add-apt-repository -y ppa:certbot/certbot

        sudo apt-get -y update
    fi

    sudo apt-get -y install certbot

    __print_divider

    certbot --version

    __print_divider
}

__install_mysql() {
    __print_header "Installing MySQL server"

    if ! which mysql >/dev/null 2>&1; then
        sudo apt-get -y install mysql-server
    fi

    __print_divider

    $(which mysql) --version

    __print_divider
}

__install_redis() {
    cd /tmp

    __print_header "Installing Redis"

    sudo curl -O http://download.redis.io/redis-stable.tar.gz

    sudo tar xzvf redis-stable.tar.gz

    cd redis-stable

    make

    sudo make install

    if [ ! -d /etc/redis ]; then
        sudo mkdir -p /etc/redis
    fi

    if [ -f /tmp/redis-stable/redis.conf ]; then
        sudo cp /tmp/redis-stable/redis.conf /etc/redis
        sudo sed -ie "s/^supervised no/supervised systemd/" /etc/redis/redis.conf
        sudo sed -ie "s/^dir .\//dir \/var\/lib\/redis/" /etc/redis/redis.conf
    fi

    sudo adduser --system --group --no-create-home redis

    if [ ! -d /var/lib/redis ]; then
        sudo mkdir -p /var/lib/redis
    fi

    sudo chown redis:redis /var/lib/redis

    sudo chmod 770 /var/lib/redis

    sudo rm -rf /etc/systemd/system/redis.service

    sudo cat >/etc/systemd/system/redis.service <<EOF
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
User=redis
Group=redis
ExecStart=/usr/local/bin/redis-server /etc/redis/redis.conf
ExecStop=/usr/local/bin/redis-cli shutdown
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl start redis
    sudo systemctl disable redis
    sudo systemctl enable redis

    __print_divider

    cd "$_PWD"
}

__install_memcached() {
    __print_header "Installing Memcached"

    sudo apt-get install -y memcached

    __print_divider
}

__install_php() {
    __print_header "Installing PHP"

    sudo apt-get -y install software-properties-common
    sudo add-apt-repository -y ppa:ondrej/php
    sudo add-apt-repository -y ppa:ondrej/nginx
    sudo apt-get -y update

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
        __print_header "Installing PHP version: ${_PHP_VERSION}"

        sudo apt-get -y install "php${_PHP_VERSION}-fpm"

        for _PHP_EXTENSION in ${_PHP_EXTENSIONS[@]}; do
            __print_header "Installing PHP extension: php${_PHP_VERSION}-${_PHP_EXTENSION}" "-"

            sudo apt-get -y install "php${_PHP_VERSION}-${_PHP_EXTENSION}"
        done

        __print_divider

        $(which "php${_PHP_VERSION}") --version

        __print_divider
    done
}

__install_composer() {
    __print_header "Installing Composer"

    sudo apt-get -y install composer

    __print_divider

    which composer

    __print_divider
}

__install_wp_cli() {
    __print_header "Installing WP-CLI"

    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    sudo mv wp-cli.phar /usr/local/bin/wp

    __print_divider

    wp --info --allow-root

    __print_divider
}

__install_nodejs() {
    __print_header "Installing NodeJS"

    local _VERSION=$(__parse_args version ${@})

    while [ -z "$_VERSION" ]; do
        read -p "Enter the version you want to install: (12)" _VERSION
        _VERSION=${_VERSION:-"12"}
    done

    if ! which nodejs >/dev/null 2>&1; then
        curl -sL "https://deb.nodesource.com/setup_${_VERSION}.x" | sudo -E bash -
    else
        local _VERSION_CURRENT_MAJOR=$(__semver $(nodejs --version) major)
        local _VERSION_MAJOR=$(__semver ${_VERSION} major)
        local _VERSION_DIFF=$(__semver_compare "$_VERSION_MAJOR" "$_VERSION_CURRENT_MAJOR")

        if [ "${_VERSION_DIFF}" != "0" ]; then
            curl -sL "https://deb.nodesource.com/setup_${_VERSION_MAJOR}.x" | sudo -E bash -
        fi
    fi

    sudo apt-get -y install nodejs

    __print_divider

    nodejs --version

    __print_divider
}

__install_yarn() {
    __print_header "Installing Yarn"

    local _VERSIONS=(stable rc nightly)
    local _VERSION=$(__parse_args version ${@})

    while [ -z "$_VERSION" ]; do
        echo -e "Select the version you want to install: (stable) "

        COLUMNS=0

        select _ITEM in ${_VERSIONS[@]}; do
            _VERSION=${_ITEM:-"stable"}
            break
        done

        COLUMNS=$_COLUMNS
    done

    if ! which yarn >/dev/null 2>&1; then
        curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
    fi

    if [ "$_VERSION" = "nightly" ]; then
        echo "deb https://nightly.yarnpkg.com/debian/ nightly main" | sudo tee /etc/apt/sources.list.d/yarn.list
    else
        echo "deb https://dl.yarnpkg.com/debian/ $_VERSION main" | sudo tee /etc/apt/sources.list.d/yarn.list
    fi

    sudo apt-get -y update

    sudo apt-get -y install yarn

    __print_divider

    yarn --version

    __print_divider
}

__pre_purge() {
    __check_os ${@}
}

__post_purge() {
    __print_header "Executing post purge scripts"

    sudo apt-get -y autoremove

    __print_divider
}

# Purge
__purge() {
    __print_header "Starting the purge procedure"
    __print_divider

    local _COMPONENTS=$(typeset -f | awk '/^__purge_/ {print $1}' | sed 's/^__purge_\+\(.*\)$/\1/')
    local _COMPONENT=$(__parse_args component ${@})

    while [[ -z "$_COMPONENT" ]]; do
        echo -e "Select component you want to purge: "

        COLUMNS=0

        select _ITEM in ${_COMPONENTS[@]}; do
            _COMPONENT=${_ITEM}
            break
        done

        COLUMNS=$_COLUMNS
    done

    declare -f -F "__purge_$_COMPONENT" >/dev/null

    if [ $? -ne 0 ]; then
        echo "Component $_COMPONENT does not exist!"
        exit 1
    fi

    eval "__purge_$_COMPONENT" ${@}
}

__purge_all() {
    __pre_purge

    __purge_yarn ${@}
    __purge_nodejs ${@}
    __purge_wp_cli ${@}
    __purge_composer ${@}
    __purge_php ${@}
    __purge_redis ${@}
    __purge_memcached ${@}
    __purge_mysql ${@}
    __purge_certbot ${@}
    __purge_nginx ${@}

    __post_purge
}

__purge_nginx() {
    __print_header "Purging NGINX"

    sudo apt-get -y purge nginx*

    sudo rm -rf /etc/nginx/lemper.io
    sudo rm -rf /var/run/lemper.io

    __print_divider
}

__purge_certbot() {
    __print_header "Purging Certbot"

    sudo apt-get -y purge certbot*

    __print_divider
}

__purge_mysql() {
    __print_header "Purging MySQL"

    sudo apt-get -y purge mysql\*

    sudo rm -rf /etc/mysql

    __print_divider
}

__purge_redis() {
    __print_header "Purging Redis"

    if [ -f /etc/systemd/system/redis.service ]; then
        sudo systemctl stop redis
        sudo systemctl disable redis
    fi

    sudo rm -rf /etc/systemd/system/redis.service

    sudo rm -rf /etc/redis
    sudo rm -rf /var/lib/redis
    sudo find /usr/local/bin -name 'redis-*' -exec rm -rf {} \;

    egrep "^redis" /etc/passwd >/dev/null

    if [ $? -eq 0 ]; then
        sudo userdel redis
    fi

    __print_divider
}

__purge_memcached() {
    __print_header "Purging Memcached"

    sudo apt-get -y --purge remove memcached\*

    __print_divider
}

__purge_php() {
    __print_header "Purging PHP"

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
        sudo service "php${_PHP_VERSION}-fpm" status | grep -i 'running\|stopped' | awk '{print $3}' | while read _STATUS; do
            if [ "$_STATUS" == "(running)" ]; then
                sudo service "php${_PHP_VERSION}-fpm" stop
            fi
        done
    done

    sudo apt-get -y --purge remove php\*

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
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

    sudo rm -rf /usr/local/bin/wp

    if [ $? -eq 0 ]; then
        echo "WP-CLI successfully purged!"
    fi

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

# Helpers
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
    IFS='--'
    read -ra _ARGUMENTS <<<"${@:2}"

    local _MATCH=""

    for _ARGUMENT in "${_ARGUMENTS[@]}"; do
        if [ -n "${_ARGUMENT}" ]; then
            IFS='='
            read -ra _PARAMS <<<"${_ARGUMENT}"

            if [ "$1" = "${_PARAMS[0]}" ]; then
                _MATCH=$(echo ${_PARAMS[1]} | sed 's/ *$//g')
            fi
        fi
    done

    echo "$_MATCH"
}

__semver() {
    local _VERSION=$(echo "${1//v/}" | awk -F'-' '{print $1}')

    local _VERSION_MAJOR=$(awk -F'.' '{print $1}' <<<$_VERSION)

    if [ -z "${_VERSION_MAJOR}" ]; then
        _VERSION_MAJOR="0"
    fi

    local _VERSION_MINOR=$(awk -F'.' '{print $2}' <<<$_VERSION)

    if [ -z "${_VERSION_MINOR}" ]; then
        _VERSION_MINOR="0"
    fi

    local _VERSION_PATCH=$(awk -F'.' '{print $3}' <<<$_VERSION)

    if [ -z "${_VERSION_PATCH}" ]; then
        _VERSION_PATCH="0"
    fi

    if [ "${2}" = "major" ]; then
        echo "${_VERSION_MAJOR}"
    elif [ "${2}" = "minor" ]; then
        echo "${_VERSION_MAJOR}.${_VERSION_MINOR}"
    else
        echo "${_VERSION_MAJOR}.${_VERSION_MINOR}.${_VERSION_PATCH}"
    fi
}

__semver_compare() {
    local version_a version_b pr_a pr_b
    # strip word "v" and extract first subset version (x.y.z from x.y.z-foo.n)
    version_a=$(echo "${1//v/}" | awk -F'-' '{print $1}')
    version_b=$(echo "${2//v/}" | awk -F'-' '{print $1}')

    if [ "$version_a" \= "$version_b" ]; then
        # check for pre-release
        # extract pre-release (-foo.n from x.y.z-foo.n)
        pr_a=$(echo "$1" | awk -F'-' '{print $2}')
        pr_b=$(echo "$2" | awk -F'-' '{print $2}')

        ####
        # Return 0 when A is equal to B
        [ "$pr_a" \= "$pr_b" ] && echo 0 && return 0

        ####
        # Return 1

        # Case when A is not pre-release
        if [ -z "$pr_a" ]; then
            echo 1 && return 0
        fi

        ####
        # Case when pre-release A exists and is greater than B's pre-release

        # extract numbers -rc.x --> x
        number_a=$(echo ${pr_a//[!0-9]/})
        number_b=$(echo ${pr_b//[!0-9]/})
        [ -z "${number_a}" ] && number_a=0
        [ -z "${number_b}" ] && number_b=0

        [ "$pr_a" \> "$pr_b" ] && [ -n "$pr_b" ] && [ "$number_a" -gt "$number_b" ] && echo 1 && return 0

        ####
        # Retrun -1 when A is lower than B
        echo -1 && return 0
    fi
    arr_version_a=(${version_a//./ })
    arr_version_b=(${version_b//./ })
    cursor=0
    # Iterate arrays from left to right and find the first difference
    while [ "$([ "${arr_version_a[$cursor]}" -eq "${arr_version_b[$cursor]}" ] && [ $cursor -lt ${#arr_version_a[@]} ] && echo true)" == true ]; do
        cursor=$((cursor + 1))
    done

    [ "${arr_version_a[$cursor]}" -gt "${arr_version_b[$cursor]}" ] && echo 1 || echo -1
}

__print_header() {
    local _CHAR=$2

    if [ -z "$_CHAR" ]; then
        _CHAR=">"
    fi

    __print_divider "${_CHAR}"
    echo -e ">>> $1"
    __print_divider "${_CHAR}"
}

__print_error() {
    local _CHAR='%'

    __print_divider "${_CHAR}"
    echo -e ">>> ERROR: $1"
    __print_divider "${_CHAR}"
}

__print_divider() {
    local _CHAR=$1

    if [ -z "$_CHAR" ]; then
        _CHAR="-"
    fi

    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' ${_CHAR}
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

__get_existing_users() {
    _l="/etc/login.defs"
    _p="/etc/passwd"

    ## get mini UID limit ##
    l=$(grep "^UID_MIN" $_l)

    ## get max UID limit ##
    l1=$(grep "^UID_MAX" $_l)

    echo $(grep -E 1[0-9]{3} /etc/passwd | sed s/:/\ / | awk '{print $1}')
}

__get_existing_sites() {
    local _DIR="/etc/nginx/lemper.io/conf/sites/${1}"

    if [ -d "${_DIR}" ]; then
        echo $(find "${_DIR}" -type f -exec basename {} \;)
    fi
}

__prompt_input() {
    unset _PROMPT_RESPONSE

    local _LABEL=$1

    if [ -z "${_LABEL}" ]; then
        _LABEL="Type response:"
    fi

    local _RESPONSE=""

    while [ -z "$_RESPONSE" ]; do
        read -p "$_LABEL " _RESPONSE
    done

    _PROMPT_RESPONSE=$_RESPONSE
}

__prompt_password() {
    unset _PROMPT_RESPONSE

    local _LABEL=$1

    if [ -z "${_LABEL}" ]; then
        _LABEL="Enter password:"
    fi

    local _RESPONSE=""

    while [ -z "$_RESPONSE" ]; do
        echo -n "${_LABEL} "

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
                    _RESPONSE="${_RESPONSE%?}"
                else
                    _PROMPT=''
                fi
            else
                _CHARCOUNT=$((_CHARCOUNT + 1))
                _PROMPT='*'
                _RESPONSE+="$ch"
            fi
        done

        stty echo

        echo
    done

    _PROMPT_RESPONSE=$_RESPONSE
}

__prompt_existing_users() {
    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _LABEL=$(__parse_args label ${@})

    if [ -z "${_LABEL}" ]; then
        _LABEL="Select existing user:"
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [ -z "$_USERNAME" ]; do

        echo "kopet"
        echo -e "${_LABEL} "

        COLUMNS=0

        select _ITEM in ${_USERS[@]}; do
            _USERNAME=$_ITEM
            break
        done

        COLUMNS=$_COLUMNS
    done

    if [ $(__is_valid_user "$_USERNAME") -ne 0 ]; then
        echo "User $_USERNAME is invalid!"
        exit 1
    fi

    echo $_USERNAME
}

__prompt_user() {
    unset _PROMPT_RESPONSE

    local _USERS=$(__get_existing_users)

    if [ -z "$_USERS" ]; then
        echo "No users available. Please add new using the 'user_add' command!"
        exit 1
    fi

    local _LABEL=$2

    if [ -z "${_LABEL}" ]; then
        _LABEL="Select existing user:"
    fi

    local _RESPONSE=$1

    while [ -z "$_RESPONSE" ]; do
        echo -e "Select existing user: "

        COLUMNS=0

        select _ITEM in ${_USERS[@]}; do
            _RESPONSE=$_ITEM
            break
        done

        COLUMNS=$_COLUMNS
    done

    if [ $(__is_valid_user "$_RESPONSE") -ne 0 ]; then
        echo "User $_RESPONSE is invalid!"
        exit 1
    fi

    _PROMPT_RESPONSE=$_RESPONSE
}

__prompt_yes_no() {
    unset _PROMPT_RESPONSE

    local _PROMPT_DEFAULT="yes"
    local _PROMPT_LABEL=$(__parse_args prompt_label ${@})
    local _RESPONSE=$(__parse_args prompt_response ${@})
    while [ -z "$_RESPONSE" ]; do
        if [ -n "$_PROMPT_LABEL" ]; then
            echo -e "$_PROMPT_LABEL "
        fi

        local _INDEX=1

        for _ITEM in "${_OPTIONS_YES_NO[@]}"; do
            if [ -n "$_PROMPT_DEFAULT" ] && [ "$_PROMPT_DEFAULT" = "$_ITEM" ]; then
                echo "$_INDEX) $_ITEM (default)"
            else
                echo "$_INDEX) $_ITEM"
            fi

            let _INDEX++
        done

        if [ -n "$_PROMPT_DEFAULT" ]; then
            _PROMPT_LABEL_CHOOSE="Choose an existing option number or press any other key for default option:"
        else
            _PROMPT_LABEL_CHOOSE="Choose an existing option number:"
        fi

        read -p "$_PROMPT_LABEL_CHOOSE " _RESPONSE

        if [[ "$_RESPONSE" =~ ^[0-9]+$ ]]; then
            _RESPONSE=${_OPTIONS_YES_NO[$(expr $_RESPONSE - 1)]:-"$_PROMPT_DEFAULT"}
        else
            _RESPONSE="$_PROMPT_DEFAULT"
        fi

        if [ -z "$_RESPONSE" ]; then
            __print_error "Invalid choice."
        fi
    done

    _PROMPT_RESPONSE=$_RESPONSE
}

__prompt_no_yes() {
    unset _PROMPT_RESPONSE

    local _PROMPT_DEFAULT="no"
    local _PROMPT_LABEL=$(__parse_args prompt_label ${@})
    local _RESPONSE=$(__parse_args prompt_response ${@})
    while [ -z "$_RESPONSE" ]; do
        if [ -n "$_PROMPT_LABEL" ]; then
            echo -e "$_PROMPT_LABEL "
        fi

        local _INDEX=1

        for _ITEM in "${_OPTIONS_NO_YES[@]}"; do
            if [ -n "$_PROMPT_DEFAULT" ] && [ "$_PROMPT_DEFAULT" = "$_ITEM" ]; then
                echo "$_INDEX) $_ITEM (default)"
            else
                echo "$_INDEX) $_ITEM"
            fi

            let _INDEX++
        done

        if [ -n "$_PROMPT_DEFAULT" ]; then
            _PROMPT_LABEL_CHOOSE="Choose an existing option number or press any other key for default option:"
        else
            _PROMPT_LABEL_CHOOSE="Choose an existing option number:"
        fi

        read -p "$_PROMPT_LABEL_CHOOSE " _RESPONSE

        if [[ "$_RESPONSE" =~ ^[0-9]+$ ]]; then
            _RESPONSE=${_OPTIONS_NO_YES[$(expr $_RESPONSE - 1)]:-"$_PROMPT_DEFAULT"}
        else
            _RESPONSE="$_PROMPT_DEFAULT"
        fi

        if [ -z "$_RESPONSE" ]; then
            __print_error "Invalid choice."
        fi
    done

    _PROMPT_RESPONSE=$_RESPONSE
}

__action_test() {
    __prompt_no_yes
    # local _DEFAULT="ddd"
    # local _USERS=($(__get_existing_users))

    # while [ -z "$_RESPONSE" ]; do
    #     echo -e "Select existing user: "

    #     local _INDEX=1
    #     for _ITEM in "${_USERS[@]}"; do
    #         echo "$_INDEX) $_ITEM"
    #         let _INDEX++
    #     done

    #     read -p "#?" _RESPONSE

    #     if [[ "$_RESPONSE" =~ ^[0-9]+$ ]]; then
    #         _RESPONSE=${_USERS[$(expr $_RESPONSE - 1)]:-"$_DEFAULT"}
    #     else
    #         _RESPONSE="$_DEFAULT"
    #     fi
    # done

    echo "_PROMPT_RESPONSE=$_PROMPT_RESPONSE"
}

# Execute the main command
__main() {
    # Check if current user have sudo access?
    sudo -v

    if [ $? -ne 0 ]; then
        exit 1
    fi

    if [ ! -d "/etc/nginx/lemper.io" ]; then
        __prompt_yes_no "--prompt_label=It is appear that you did not install the LEMPER.IO yet. Would you like to install it now ?"

        if [ "${_PROMPT_RESPONSE}" != "yes" ]; then
            echo "Goodbye!"
            exit 1
        fi

        __install
    else
        _CALLBACK=$(echo ${1} | sed 's/^_\+\(.*\)$/\1/')

        if [ "${_CALLBACK}" = "install" ]; then
            __install ${@:2}
        elif [ "${_CALLBACK}" = "purge" ]; then
            __purge ${@:2}
        else
            local _CALLBACKS=$(typeset -f | awk '/^__action_/ {print $1}' | sed 's/^__action_\+\(.*\)$/\1/')

            while [[ -z "$_CALLBACK" ]]; do
                echo -e "Select action you want to execute: "

                COLUMNS=0

                select _ITEM in ${_CALLBACKS[@]}; do
                    _CALLBACK=${_ITEM}
                    break
                done

                COLUMNS=$_COLUMNS
            done

            declare -f -F "__action_$_CALLBACK" >/dev/null

            if [ $? -ne 0 ]; then
                echo "Function _$_CALLBACK does not exist!"
                exit 1
            fi

            eval "__action_$_CALLBACK" ${@:2}
        fi
    fi
}

__main $@
