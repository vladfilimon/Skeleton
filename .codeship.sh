#!/usr/bin/env bash

# Argument 1: Text
bold() {
    echo -e "\e[1m$1\e[0;20m"
}

# Argument 1: Text
bold_green() {
    echo -e "\e[33;1m$1\e[0;20m"
}

# Argument 1: Action
# Argument 2: Subject
print_header() {
    echo -e "$(bold "$1"): $(bold_green "$2")"
}

# Argument 1: Command to run
run_command() {
    echo "> $1"

    eval "$1"
}

export APP_NAME_CACHE_DIR=$HOME/cache

print_header "Setting up mysql" "AppName"
export MYSQL_DIR="$HOME/mysql-5.7"
export MYSQL_PORT="3307"
export MYSQL_SOCKET="$MYSQL_DIR/socket/mysqld.sock"
export PATH="$MYSQL_DIR/bin:$PATH"
run_command "\curl -sSL https://raw.githubusercontent.com/codeship/scripts/master/packages/mysql-5.7.sh | bash -s"

# Set php version
phpenv local 7.2
run_command "php -v"

# Set node version
run_command "nvm alias default 10.16.0"

print_header "Activating memcached extension" "AppName"
run_command "printf \"/usr \n\n\n\n\n\n\nno\n\" | pecl install memcached" || exit $?

print_header "Memory limit" "AppName"
run_command "sed -i'' 's/^memory_limit=.*/memory_limit = -1/g' ${HOME}/.phpenv/versions/$(phpenv version-name)/etc/php.ini" || exit $?

print_header "Disable xdebug"
run_command "rm -f /home/rof/.phpenv/versions/$(phpenv version-name)/etc/conf.d/xdebug.ini"

print_header "Setting up php libsodium extension"
run_command "\curl -sSL https://raw.githubusercontent.com/codeship/scripts/master/packages/libsodium.sh | bash -s"
run_command "LD_LIBRARY_PATH=$HOME/cache/libsodium/lib PKG_CONFIG_PATH=$HOME/cache/libsodium/lib/pkgconfig LDFLAGS=\"-L$HOME/cache/libsodium/lib\" pecl install libsodium"

# Download and configure Symfony webserver
print_header "Downloading Symfony CLI" "Sylius"
if [ ! -f $APP_NAME_CACHE_DIR/symfony ]; then
    run_command "wget https://get.symfony.com/cli/installer -O - | bash"
    run_command "mv ~/.symfony/bin/symfony $APP_NAME_CACHE_DIR"
fi
run_command "$APP_NAME_CACHE_DIR/symfony version"

print_header "Installing dependencies" "AppName"
run_command "composer install --no-interaction --prefer-dist" || exit $?
run_command "composer dump-env test" || exit $?

# Set node version
run_command "nvm alias default 10.16.0"
run_command "nvm use 10.16.0"

print_header "Setting the application up" "AppName"
run_command "APP_DEBUG=1 bin/console doctrine:database:create -vvv" || exit $? # Have to be run with debug = true, to omit generating proxies before setting up the database
run_command "APP_DEBUG=1 APP_ENV=dev bin/console cache:warmup -vvv" || exit $? # For PHPStan
run_command "bin/console cache:warmup -vvv" || exit $? # For tests
run_command "bin/console doctrine:migrations:migrate --no-interaction -vvv" || exit $?

print_header "Setting the web assets up" "AppName"
run_command "bin/console assets:install public -vvv" || exit $?
run_command "yarn install && yarn run encore production" || exit $?

# Configure display
run_command "/sbin/start-stop-daemon --start --quiet --pidfile /tmp/xvfb_99.pid --make-pidfile --background --exec /usr/bin/Xvfb -- :99 -ac -screen 0 2880x1800x16"
run_command "export DISPLAY=:99"

# Download and configure ChromeDriver
if [ ! -f $APP_NAME_CACHE_DIR/chromedriver ] || [ "$($APP_NAME_CACHE_DIR/chromedriver --version | grep -c 2.34)" = "0" ]; then
    run_command "curl https://chromedriver.storage.googleapis.com/86.0.4240.22/chromedriver_linux64.zip > chromedriver.zip"
    run_command "unzip chromedriver.zip"
    run_command "chmod +x chromedriver"
    run_command "mv chromedriver $APP_NAME_CACHE_DIR"
fi

# Run ChromeDriver
run_command "$APP_NAME_CACHE_DIR/chromedriver > /dev/null 2>&1 &"

# Download and configure Selenium
if [ ! -f $APP_NAME_CACHE_DIR/selenium.jar ] || [ "$(java -jar $APP_NAME_CACHE_DIR/selenium.jar --version | grep -c 3.4.0)" = "0" ]; then
    run_command "curl http://selenium-release.storage.googleapis.com/3.4/selenium-server-standalone-3.4.0.jar > selenium.jar"
    run_command "mv selenium.jar $APP_NAME_CACHE_DIR"
fi

# Run Selenium
run_command "java -Dwebdriver.chrome.driver=$APP_NAME_CACHE_DIR/chromedriver -jar $APP_NAME_CACHE_DIR/selenium.jar > /dev/null 2>&1 &"

# Run webserver
run_command "$APP_NAME_CACHE_DIR/symfony server:ca:install"
run_command "$APP_NAME_CACHE_DIR/symfony server:start --port=8080 --dir=public --force-php-discovery --daemon"
