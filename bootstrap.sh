#!/usr/bin/env bash

# Add PHP 5.4 PPA
# --------------------
apt-get update
apt-get install -y python-software-properties
add-apt-repository ppa:ondrej/php5-oldstable -y
apt-get update
apt-get dist-upgrade

# Install Apache & PHP
# --------------------
apt-get install -y apache2
apt-get install -y php5
apt-get install -y libapache2-mod-php5
apt-get install -y php5-mysql php5-curl php5-gd php5-intl php-pear php5-imap php5-mcrypt php5-ming php5-ps php5-pspell php5-recode php5-snmp php5-sqlite php5-tidy php5-xmlrpc php5-xsl php-apc

# Delete default apache web dir and symlink mounted vagrant dir from host machine
# --------------------
rm -rf /var/www
mkdir /vagrant/httpdocs
ln -fs /vagrant/httpdocs /var/www

# Replace contents of default Apache vhost
# --------------------
VHOST=$(cat <<EOF
<VirtualHost *:80>
  DocumentRoot "/var/www"
  ServerName localhost
  <Directory "/var/www">
    AllowOverride All
  </Directory>
</VirtualHost>
<VirtualHost *:8080>
  DocumentRoot "/var/www"
  ServerName localhost
  <Directory "/var/www">
    AllowOverride All
  </Directory>
</VirtualHost>
EOF
)

echo "$VHOST" > /etc/apache2/sites-enabled/000-default

a2enmod rewrite
service apache2 restart

# Mysql
# --------------------
# Ignore the post install questions
export DEBIAN_FRONTEND=noninteractive
# Install MySQL quietly
apt-get -q -y install mysql-server-5.5

mysql -u root -e "CREATE DATABASE IF NOT EXISTS magentodb"
mysql -u root -e "GRANT ALL PRIVILEGES ON magentodb.* TO 'magentouser'@'localhost' IDENTIFIED BY 'password'"
mysql -u root -e "FLUSH PRIVILEGES"

# Magento
# --------------------
# http://www.magentocommerce.com/wiki/1_-_installation_and_configuration/installing_magento_via_shell_ssh

# Download and extract
if [ ! -f "/vagrant/httpdocs/index.php" ]; then
  cd /vagrant/httpdocs
  wget http://www.magentocommerce.com/downloads/assets/1.9.0.1/magento-1.9.0.1.tar.gz
  tar -zxvf magento-1.9.0.1.tar.gz
  mv magento/* magento/.htaccess .
  chmod -R o+w media var
  chmod o+w app/etc
  # Clean up downloaded file and extracted dir
  rm -rf magento*
fi

# Run installer
if [ ! -f "/vagrant/httpdocs/app/etc/local.xml" ]; then
  cd /vagrant/httpdocs
  sudo /usr/bin/php -f install.php -- --license_agreement_accepted yes --locale en_US --timezone "America/Los_Angeles" --default_currency USD --db_host localhost --db_name magentodb --db_user magentouser --db_pass password --url "http://127.0.0.1:8080/" --use_rewrites yes --use_secure no --secure_base_url "http://127.0.0.1:8080/" --use_secure_admin no --skip_url_validation yes --admin_lastname Owner --admin_firstname Store --admin_email "admin@example.com" --admin_username admin --admin_password password123123
fi

# Install n98-magerun
# --------------------
cd /vagrant/httpdocs
wget https://raw.github.com/netz98/n98-magerun/master/n98-magerun.phar
chmod +x ./n98-magerun.phar
sudo mv ./n98-magerun.phar /usr/local/bin/

cd /usr/local/bin
ln -s n98-magerun.phar mr

wget https://phar.phpunit.de/phpunit.phar
chmod +x phpunit.phar
ln -s phpunit.phar phpunit

apt-get install -y curl git
curl -sS https://getcomposer.org/installer | php
ln -s composer.phar composer
cd /usr/src/
git clone git://github.com/Behat/Behat.git 
cd Behat
git submodule update --init
composer install
cp bin/behat /usr/local/bin/
cd /usr/src/
git clone https://github.com/phpspec/phpspec
cd phpspec
composer install
cp bin/phpspec /usr/local/bin/
cd /var/www/
COMPOSER=$(cat <<EOF
{
    "require-dev": {
        "magetest/magento-behat-extension": "dev-develop",
        "magetest/magento-phpspec-extension": "~2.0"
    },
     "require": {
        "php": ">=5.3.0"
    },
    "config": {
        "bin-dir": "bin"
    },
    "autoload": {
        "psr-0": {
            "": [
                "public/app",
                "public/app/code/local",
                "public/app/code/community",
                "public/app/code/core",
                "public/lib"
            ]
        }
    },
    "minimum-stability": "dev"
}
EOF
)
echo "$COMPOSER" > /var/www/composer.json
cd /var/www/
composer install --dev --prefer-dist --no-interaction
PHPSPEC=$(cat <<EOF
extensions: [MageTest\PhpSpec\MagentoExtension\Extension]
mage_locator:
  spec_prefix: 'spec'
  src_path: 'public/app/code'
  spec_path: 'spec/public/app/code'
  code_pool: 'community'
EOF
)
echo "$PHPSPEC" > /var/www/phpspec.yml
BEHAT=$(cat <<EOF
default:
  extensions:
    MageTest\MagentoExtension\Extension:
      base_url: "http://project.development.local"
EOF
)
echo "$BEHAT" > /var/www/behat.yml
bin/behat --init
rm /var/www/composer.lock
composer update
cd /usr/local/src/
git clone https://github.com/colinmollenhour/modman
cd modman
cp modman /usr/local/bin/
chmod a+x /usr/local/bin/modman
pear install PHP_CodeSniffer

rm /etc/php5/cli/conf.d/ming.ini
MINGFIX=$(cat <<EOF
extension=ming.so
EOF
)
echo "$MINGFIX" > /etc/php5/cli/conf.d/ming.ini
