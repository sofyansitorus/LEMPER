#!/bin/bash

_APT_REPOSITORIES=(ondrej/php)
_COMMON_PACKAGES=(software-properties-common dialog apt-utils gcc g++ make curl wget git zip unzip)
_PHP_VERSIONS=(5.6 7.0 7.1 7.2 7.3 7.4)
_PHP_EXTENSIONS=(cli fpm gd mysql curl zip xdebug)
_SITE_PRESETS=(php wordpress drupal magento)
_DB_NAME=""
_DB_USER=""
_DB_PASSWORD=""
_DB_HOST=""

_check_os() {
    __print_header "Checking operating system requirements"

    if ! grep -q 'debian' /etc/os-release; then
        echo "Script only supported for Debian operating system family"
        exit 1
    fi

    cat /etc/os-release

    __print_divider
}

_install() {
    __print_header "Starting the install procedure"
    __print_divider

    _check_os

    __add_ppa

    __install_common ${@}
    __install_nginx ${@}
    __install_mariadb ${@}
    __install_php ${@}
    __install_composer ${@}
    __install_wp_cli ${@}
    __install_nodejs ${@}
    __install_yarn ${@}

    __cleaning_up
}

_purge() {
    __print_header "Starting the purge procedure"
    __print_divider

    _check_os

    __purge_yarn ${@}
    __purge_nodejs ${@}
    __purge_wp_cli ${@}
    __purge_composer ${@}
    __purge_php ${@}
    __purge_mariadb ${@}
    __purge_nginx ${@}

    __cleaning_up
}

_user_add() {
    __print_header "Adding new user"

    if [ $(id -u) -ne 0 ]; then
        echo "Only root may add a user to the system"
        exit 1
    fi

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter username: " _USERNAME
    done

    egrep "^$_USERNAME" /etc/passwd >/dev/null

    if [ $? -eq 0 ]; then
        echo "User $_USERNAME already exists!"
        exit 1
    fi

    local _PASSWORD=$(__parse_args password ${@})

    while [[ -z "$_PASSWORD" ]]; do
        read -p "Enter password: " _PASSWORD
    done

    local _CRYPTED_PASS=$(perl -e 'print crypt($ARGV[0], "password")' $_PASSWORD)

    useradd -m -p $_CRYPTED_PASS $_USERNAME

    if [ $? -ne 0 ]; then
        echo -e "Failed to add a user!"
    fi

    echo -e "User $_USERNAME has been added to system!"

    __print_divider

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
        _php_fpm_pool_create "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}"
    done
}

_user_del() {
    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter username: " _USERNAME
    done

    egrep "^$_USERNAME" /etc/passwd >/dev/null

    if [ $? -ne 0 ]; then
        echo "User $_USERNAME not exists!"
        exit 1
    fi

    if [ "$_USERNAME" = "root" ]; then
        echo "User root cannot be deleted"
        exit 1
    fi

    for _PHP_VERSION in ${_PHP_VERSIONS[@]}; do
        _php_fpm_pool_delete "--php_version=${_PHP_VERSION}" "--username=${_USERNAME}"
    done

    __print_header "Deleting existing user"

    userdel -r "$_USERNAME"

    echo -e "User $_USERNAME has been deleted from system!"

    __print_divider
}

_php_fpm_pool_create() {
    __print_header "Adding PHP-FPM pool"

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter Username: " _USERNAME
    done

    egrep "^$_USERNAME" /etc/passwd >/dev/null

    if [ $? -ne 0 ]; then
        echo "User $_USERNAME not exists!"
        exit 1
    fi

    local _PHP_VERSION=$(__parse_args php_version ${@})

    while [[ -z "$_PHP_VERSION" ]]; do
        read -p "Enter PHP Version: " _PHP_VERSION
    done

    local _POOL_CONF_SRC="/etc/php/${_PHP_VERSION}/fpm/pool.d/www.conf"

    if ! [ -f "$_POOL_CONF_SRC" ]; then
        echo "File $_POOL_CONF_SRC not exist"
        exit 1
    fi

    local _POOL_CONF_DEST="/etc/php/${_PHP_VERSION}/fpm/pool.d/${_USERNAME}.conf"

    if [ -f "$_POOL_CONF_DEST" ]; then
        echo "File $_POOL_CONF_DEST already exist"
        exit 1
    fi

    echo "Copying file $_POOL_CONF_SRC ===>>> ${_POOL_CONF_DEST}"

    sudo cp "${_POOL_CONF_SRC}" "${_POOL_CONF_DEST}"

    sed -i -e "s/\[www\]/\[${_USERNAME}\]/g" "${_POOL_CONF_DEST}"
    sed -i -e "s/www-data/${_USERNAME}/g" "${_POOL_CONF_DEST}"
    sed -i -e "s/listen.owner = ${_USERNAME}/listen.owner = www-data/g" "${_POOL_CONF_DEST}"
    sed -i -e "s/listen.group = ${_USERNAME}/listen.group = www-data/g" "${_POOL_CONF_DEST}"
    sed -i -e "s/\/run\/php\/php${_PHP_VERSION}-fpm\.sock/\/run\/php\/php${_PHP_VERSION}-fpm-${_USERNAME}\.sock/g" "${_POOL_CONF_DEST}"

    sudo service "php${_PHP_VERSION}-fpm" restart

    __print_divider
}

_php_fpm_pool_delete() {
    __print_header "Deleting PHP-FPM pool"

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter Username: " _USERNAME
    done

    egrep "^$_USERNAME" /etc/passwd >/dev/null

    if [ $? -ne 0 ]; then
        echo "User $_USERNAME not exists!"
        exit 1
    fi

    local _PHP_VERSION=$(__parse_args php_version ${@})

    while [[ -z "$_PHP_VERSION" ]]; do
        read -p "Enter PHP Version: " _PHP_VERSION
    done

    local _POOL_CONF_DEST="/etc/php/${_PHP_VERSION}/fpm/pool.d/${_USERNAME}.conf"

    if ! [ -f "$_POOL_CONF_DEST" ]; then
        echo "File $_POOL_CONF_DEST not exist"
        exit 1
    fi

    echo "Deleting file ${_POOL_CONF_DEST}"

    sudo rm -rf "${_POOL_CONF_DEST}"

    sudo service "php${_PHP_VERSION}-fpm" restart

    __print_divider
}

_site_add() {
    __print_header "Adding new site"

    local _USERNAME=$(__parse_args username ${@})

    while [[ -z "$_USERNAME" ]]; do
        read -p "Enter username: [$USER]" _USERNAME
        _USERNAME=${_USERNAME:-$USER}
    done

    egrep "^$_USERNAME" /etc/passwd >/dev/null

    if [ $? -ne 0 ]; then
        echo "User $_USERNAME not exists!"
        exit 1
    fi

    local _DOMAIN=$(__parse_args domain ${@})

    while [[ -z "$_DOMAIN" ]]; do
        read -p "Enter domain: " _DOMAIN
    done

    local _SUBDOMAIN=$(__parse_args subdomain ${@})

    if [ -z "$_SUBDOMAIN" ]; then
        read -p "Enter subdomain: " _SUBDOMAIN
    fi

    local _ENABLE_SSL=$(__parse_args enable_ssl ${@})

    if [ -z "$_ENABLE_SSL" ]; then
        read -p "Do you want to enable SSL (y/n)? " _ENABLE_SSL

        case ${_ENABLE_SSL:0:1} in
        y | Y | yes)
            _ENABLE_SSL="yes"
            ;;
        *)
            _ENABLE_SSL="no"
            ;;
        esac
    fi

    local _PHP_VERSION=$(__parse_args php_version ${@})

    if [ -z "$_PHP_VERSION" ]; then
        echo -e "Select the PHP version configuration"

        select _ITEM in ${_PHP_VERSIONS[@]}; do
            _PHP_VERSION=$_ITEM
            break
        done
    fi

    local _SITE_PRESET=$(__parse_args site_preset ${@})

    if [ -z "$_SITE_PRESET" ]; then
        echo -e "Select site configuration preset"

        select _ITEM in ${_SITE_PRESETS[@]}; do
            _SITE_PRESET=$_ITEM
            break
        done
    fi

    local _CREATE_DATABASE=$(__parse_args database_add ${@})

    if [ -z "$_CREATE_DATABASE" ]; then
        read -p "Do you want to create database (y/n)? " _CREATE_DATABASE

        case ${_CREATE_DATABASE:0:1} in
        y | Y | yes)
            _CREATE_DATABASE="yes"
            ;;
        *)
            _CREATE_DATABASE="no"
            ;;
        esac
    fi

    if [ "$_CREATE_DATABASE" = "yes" ]; then
        _database_add ${@}
    fi

    echo "_USERNAME=$_USERNAME"
    echo "_DOMAIN=$_DOMAIN"
    echo "_SUBDOMAIN=$_SUBDOMAIN"
    echo "_ENABLE_SSL=$_ENABLE_SSL"
    echo "_PHP_VERSION=$_PHP_VERSION"
    echo "_SITE_PRESET=$_SITE_PRESET"
    echo "_CREATE_DATABASE=$_CREATE_DATABASE"
    echo "_DB_NAME=$_DB_NAME"
    echo "_DB_USER=$_DB_USER"
    echo "_DB_PASSWORD=$_DB_PASSWORD"
    echo "_DB_HOST=$_DB_HOST"

    __print_divider
}

_database_add() {
    _BIN_MYSQL=$(which mysql)

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
        read -p "Enter MySQL database password: " _DB_PASSWORD
    done

    _DB_HOST=$(__parse_args db_host ${@})

    while [[ -z "$_DB_HOST" ]]; do
        read -p "Enter MySQL hostname: [%]" _DB_HOST
        _DB_HOST=${_DB_HOST:-"%"}
    done

    local _MYSQL_ROOT_PASSWORD=$(__parse_args mysql_root_password ${@})

    while [[ -z "$_MYSQL_ROOT_PASSWORD" ]]; do
        read -p "Enter MySQL Root Password: [root]" _MYSQL_ROOT_PASSWORD
        _MYSQL_ROOT_PASSWORD=${_MYSQL_ROOT_PASSWORD:-"root"}
    done

    local _SQL_CREATE_DATABASE="CREATE DATABASE IF NOT EXISTS ${_DB_NAME};"
    local _SQL_CREATE_USER="CREATE USER IF NOT EXISTS '${_DB_USER}'@'${_DB_HOST}' IDENTIFIED BY '${_DB_PASSWORD}';"
    local _SQL_GRANT="GRANT ALL PRIVILEGES ON ${_DB_NAME}.* TO '${_DB_USER}'@'${_DB_HOST}';"
    local _SQL_FLUSH="FLUSH PRIVILEGES;"

    $_BIN_MYSQL -u root -p${_MYSQL_ROOT_PASSWORD} -e "${_SQL_CREATE_DATABASE}${_SQL_CREATE_USER}${_SQL_GRANT}${_SQL_FLUSH}"
}

__parse_args() {
    local _MATCH=""

    for _ARGUMENT in "${@:2}"; do
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
            __print_header "Adding ppa:$_APT_REPOSITORIY"

            sudo add-apt-repository -y ppa:$_APT_REPOSITORIY

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
            read -p "Enter MySQL Root Password: [root]" _MYSQL_ROOT_PASSWORD
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

# Execute the main command
__main() {
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
