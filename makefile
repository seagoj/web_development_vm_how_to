###
# This makefile more or less automates the procedures set out at
# https://github.com/triplepoint/web_development_vm_how_to
#
# Please refer to that guide for more information.
###


### Global configuration
SHELL := /usr/bin/env bash
TOOL_DIR = $(CURDIR)
SOURCE_DOWNLOAD_DIR = $(TOOL_DIR)/source_downloads
GENERATED_PACKAGE_DIR = $(TOOL_DIR)/generated_packages
WORKING_DIR = /tmp/makework

### Nginx Configuration
NGINX_VERSION = 1.4.1

### PHP Configuration
PHP_VERSION = 5.5.0

### Symlink target for /var/www
WWW_DIRECTORY_SYMLINK_TARGET = /projects

### MySQL Configuration
# Note that the URL this is sourced from is a needlessly-complex URL scheme at mysql.com  Any version other
# than a 5.6.x version will likely require the URL to be reviewed and modified.  See down below for where this
# is used in the URL fragment
MYSQL_VERSION = 5.6.12

### YUI Compressor
YUI_COMPRESSOR_VERSION = 2.4.7


target-list :
	@echo "This makefile builds packages from source for a PHP-enabled web server."
	@echo
	@echo "To build the server:"
	@echo "    make php_web_server"
	@echo


php_web_server : firewall_config www_directory_symlink yui_compressor_install compass_install nginx_install php_install mysql_install


###############################################################


clean :
	-rm -rf $(WORKING_DIR)
	-rm -rf $(SOURCE_DOWNLOAD_DIR)

gdebi_install :
	@if [ "`which gdebi`" = "" ]; then		\
		apt-get update &&					\
		apt-get install -y gdebi-core; 		\
	fi

fpm_install :
	@if [ "`which fpm`" = "" ]; then		\
		apt-get update &&					\
		apt-get install -y ruby &&			\
		gem install fpm; 					\
	fi

firewall_config :
	ufw default deny
	ufw allow ssh
	ufw allow http
	ufw allow 443
	ufw --force enable


www_directory_symlink :
	-ln -s $(WWW_DIRECTORY_SYMLINK_TARGET) /var/www


get_yui_compressor_source :
	@if [ ! -f $(SOURCE_DOWNLOAD_DIR)/yuicompressor-$(YUI_COMPRESSOR_VERSION).zip ]; then					\
		mkdir -p $(SOURCE_DOWNLOAD_DIR) && cd $(SOURCE_DOWNLOAD_DIR) &&										\
		wget https://github.com/downloads/yui/yuicompressor/yuicompressor-$(YUI_COMPRESSOR_VERSION).zip;	\
	fi

yui_compressor_install : get_yui_compressor_source
	apt-get update
	apt-get install -y unzip default-jre

	mkdir -p $(WORKING_DIR) && cd $(WORKING_DIR) &&																								\
	#																																			\
	cp $(SOURCE_DOWNLOAD_DIR)/yuicompressor-$(YUI_COMPRESSOR_VERSION).zip . &&																	\
	unzip yuicompressor-$(YUI_COMPRESSOR_VERSION).zip &&																						\
	#																																			\
	mkdir -p /usr/share/yui-compressor &&																										\
	cp yuicompressor-$(YUI_COMPRESSOR_VERSION)/build/yuicompressor-$(YUI_COMPRESSOR_VERSION).jar /usr/share/yui-compressor/yui-compressor.jar


compass_install :
	apt-get update
	apt-get install -y ruby

	gem install compass
	-ln -s `which compass` /usr/bin/compass


cache_nginx_source :
	@if [ ! -f $(SOURCE_DOWNLOAD_DIR)/nginx-$(NGINX_VERSION).tar.gz ]; then	\
		mkdir -p $(SOURCE_DOWNLOAD_DIR) && cd $(SOURCE_DOWNLOAD_DIR) &&		\
		wget http://nginx.org/download/nginx-$(NGINX_VERSION).tar.gz;		\
	fi

install_nginx_dependencies :
	apt-get update
	apt-get install -y make libc6 libpcre3 libpcre3-dev libpcrecpp0 libssl0.9.8 libssl-dev zlib1g zlib1g-dev lsb-base

nginx_build : cache_nginx_source install_nginx_dependencies
	mkdir -p $(WORKING_DIR)

	cp $(SOURCE_DOWNLOAD_DIR)/nginx-$(NGINX_VERSION).tar.gz $(WORKING_DIR)
	tar -C $(WORKING_DIR) -xvf $(WORKING_DIR)/nginx-$(NGINX_VERSION).tar.gz

	cd $(WORKING_DIR)/nginx-$(NGINX_VERSION) &&								\
	./configure																\
		--prefix=/usr														\
		--sbin-path=/usr/sbin												\
		--pid-path=/var/run/nginx.pid										\
		--conf-path=/etc/nginx/nginx.conf									\
		--error-log-path=/var/log/nginx/error.log							\
		--http-log-path=/var/log/nginx/access.log							\
		--user=www-data --group=www-data									\
		--with-http_ssl_module												\
		--with-http_spdy_module												\
		--with-ipv6  &&														\
	#																		\
	$(MAKE)

nginx_package : fpm_install nginx_build
	mkdir -p $(WORKING_DIR)/nginx-$(NGINX_VERSION)-install

	# Install NGINX into a directory suitable for turning into a package
	cd $(WORKING_DIR)/nginx-$(NGINX_VERSION) &&									\
	$(MAKE) install DESTDIR=$(WORKING_DIR)/nginx-$(NGINX_VERSION)-install

	# Set up the Nginx FPM init script
	mkdir -p $(WORKING_DIR)/nginx-$(NGINX_VERSION)-install/etc/init.d/
	cp $(TOOL_DIR)/etc/init.d/nginx-init $(WORKING_DIR)/nginx-$(NGINX_VERSION)-install/etc/init.d/nginx
	chmod 755 $(WORKING_DIR)/nginx-$(NGINX_VERSION)-install/etc/init.d/nginx

	# Set up the Nginx config file and its config directories
	mkdir -p $(WORKING_DIR)/nginx-$(NGINX_VERSION)-install/etc/nginx/sites-available
	mkdir -p $(WORKING_DIR)/nginx-$(NGINX_VERSION)-install/etc/nginx/sites-enabled

	# Make the log directories
	mkdir -p $(WORKING_DIR)/nginx-$(NGINX_VERSION)-install/var/log/nginx
	chown www-data:www-data $(WORKING_DIR)/nginx-$(NGINX_VERSION)-install/var/log/nginx

	# Generate the package
	mkdir -p $(GENERATED_PACKAGE_DIR) && cd $(GENERATED_PACKAGE_DIR) &&     \
	fpm -s dir -t deb -n nginx 												\
		-v $(NGINX_VERSION) 												\
		-C $(WORKING_DIR)/nginx-$(NGINX_VERSION)-install					\
		-d libc6 															\
		-d libpcre3                                                         \
		-d libpcre3-dev                                                     \
		-d libpcrecpp0                                                      \
		-d libssl0.9.8                                                      \
		-d libssl-dev                                                       \
		-d zlib1g                                                           \
		-d zlib1g-dev                                                       \
		-d lsb-base                                                         \
		etc 																\
		var/log/nginx

nginx_install : gdebi_install
	### All this stuff should be handled by puppet
	gdebi -n $(GENERATED_PACKAGE_DIR)/nginx_$(NGINX_VERSION)*.deb

	update-rc.d nginx defaults

	cp $(TOOL_DIR)/etc/nginx/nginx.conf /etc/nginx/
	cp $(TOOL_DIR)/etc/nginx/sites-available/* /etc/nginx/sites-available

	service nginx start

cache_php_source :
	@if [ ! -f $(SOURCE_DOWNLOAD_DIR)/php-$(PHP_VERSION).tar.bz2 ]; then												\
		mkdir -p $(SOURCE_DOWNLOAD_DIR) && cd $(SOURCE_DOWNLOAD_DIR) &&													\
		wget http://www.php.net/get/php-$(PHP_VERSION).tar.bz2/from/this/mirror -O php-$(PHP_VERSION).tar.bz2;			\
	fi

install_php_dependencies :
	apt-get update
	apt-get install -y make autoconf libxml2 libxml2-dev libcurl3 libcurl4-gnutls-dev libmagic-dev

php_build : cache_php_source install_php_dependencies
	mkdir -p $(WORKING_DIR)

	cp $(SOURCE_DOWNLOAD_DIR)/php-$(PHP_VERSION).tar.bz2 $(WORKING_DIR)
	tar -C $(WORKING_DIR) -xvf $(WORKING_DIR)/php-$(PHP_VERSION).tar.bz2

	cd $(WORKING_DIR)/php-$(PHP_VERSION) &&									\
	./configure																\
		--prefix=/usr														\
		--sysconfdir=/etc                                                   \
		--with-config-file-path=/etc										\
		--without-pear														\
		--enable-fpm														\
		--with-fpm-user=www-data											\
		--with-fpm-group=www-data											\
		--enable-opcache    												\
		--enable-mbstring													\
		--enable-mbregex													\
		--with-mysqli														\
		--with-openssl														\
		--with-curl															\
		--with-zlib &&														\
	#																		\
	$(MAKE)

php_package : fpm_install #php_build
	mkdir -p $(WORKING_DIR)/php-$(PHP_VERSION)-install

	# Install PHP into a directory suitable for turning into a package
	cd $(WORKING_DIR)/php-$(PHP_VERSION) &&									\
	$(MAKE) install INSTALL_ROOT=$(WORKING_DIR)/php-$(PHP_VERSION)-install

	# Set up the PHP FPM init script
	mkdir -p $(WORKING_DIR)/php-$(PHP_VERSION)-install/etc/init.d/
	cp $(WORKING_DIR)/php-$(PHP_VERSION)/sapi/fpm/init.d.php-fpm $(WORKING_DIR)/php-$(PHP_VERSION)-install/etc/init.d/php-fpm
	chmod 755 $(WORKING_DIR)/php-$(PHP_VERSION)-install/etc/init.d/php-fpm

	# Set up PHP FPM config file, configured to work with the Nginx socket as configured in Nginx earlier
	mkdir -p $(WORKING_DIR)/php-$(PHP_VERSION)-install/etc/
	cp $(WORKING_DIR)/php-$(PHP_VERSION)-install/etc/php-fpm.conf.default $(WORKING_DIR)/php-$(PHP_VERSION)-install/etc/php-fpm.conf
	sed -i 's/;pid = /pid = /g' $(WORKING_DIR)/php-$(PHP_VERSION)-install/etc/php-fpm.conf
	sed -i 's/;error_log = log\/php-fpm.log/error_log = \/var\/log\/php-fpm\/php-fpm.log/g' $(WORKING_DIR)/php-$(PHP_VERSION)-install/etc/php-fpm.conf
	sed -i 's/listen = 127.0.0.1:9000/listen = \/tmp\/php.socket/g' $(WORKING_DIR)/php-$(PHP_VERSION)-install/etc/php-fpm.conf

	# Make the log directories
	mkdir -p $(WORKING_DIR)/php-$(PHP_VERSION)-install/var/log/php-fpm
	chown www-data:www-data $(WORKING_DIR)/php-$(PHP_VERSION)-install/var/log/php-fpm
	mkdir -p $(WORKING_DIR)/php-$(PHP_VERSION)-install/var/log/php
	chown www-data:www-data $(WORKING_DIR)/php-$(PHP_VERSION)-install/var/log/php

	# Generate the package
	mkdir -p $(GENERATED_PACKAGE_DIR) && cd $(GENERATED_PACKAGE_DIR) &&     \
	fpm -s dir -t deb -n php 												\
		-v $(PHP_VERSION) 													\
		-C $(WORKING_DIR)/php-$(PHP_VERSION)-install  						\
		-d libxml2 															\
		-d libxml2-dev														\
		-d libcurl3 														\
		-d libcurl4-gnutls-dev 												\
		-d libmagic-dev 													\
		usr/lib/php/extensions/no-debug-non-zts-20121212/ 					\
		usr/bin 															\
		usr/php/man/man1 													\
		usr/sbin 															\
		etc 																\
		usr/php/man/man8 													\
		usr/php/fpm 														\
		usr/lib/php/build 													\
		usr/include/php                                                     \
		var/log/php-fpm                                                     \
		var/log/php

php_install : gdebi_install
	### All this stuff should be handled by puppet
	gdebi -n $(GENERATED_PACKAGE_DIR)/php_$(PHP_VERSION)*.deb

	update-rc.d php-fpm defaults

	pecl update-channels
	printf "\n" | pecl install pecl_http xdebug

	cp $(TOOL_DIR)/etc/php.ini /etc/php.ini

	service php-fpm start


mysql_user :
	groupadd mysql &&														\
	useradd -c "MySQL Server" -r -g mysql mysql

cache_mysql_source :
	@if [ ! -f $(SOURCE_DOWNLOAD_DIR)/mysql-$(MYSQL_VERSION).tar.gz ]; then				\
		mkdir -p $(SOURCE_DOWNLOAD_DIR) && cd $(SOURCE_DOWNLOAD_DIR) &&					\
		wget http://cdn.mysql.com/Downloads/MySQL-5.6/mysql-$(MYSQL_VERSION).tar.gz;	\
	fi

install_mysql_dependencies :
	apt-get update
	apt-get install -y make build-essential cmake libaio-dev libncurses5-dev

mysql_build : cache_mysql_source install_mysql_dependencies
	mkdir -p $(WORKING_DIR)

	cp $(SOURCE_DOWNLOAD_DIR)/mysql-$(MYSQL_VERSION).tar.gz $(WORKING_DIR)
	tar -C $(WORKING_DIR) -xvf $(WORKING_DIR)/mysql-$(MYSQL_VERSION).tar.gz

	mkdir -p $(WORKING_DIR)/mysql-$(MYSQL_VERSION)/build && cd $(WORKING_DIR)/mysql-$(MYSQL_VERSION)/build 	\
	cmake																									\
		-DCMAKE_INSTALL_PREFIX=$(WORKING_DIR)/mysql-$(MYSQL_VERSION)-install/usr/share/mysql				\
		-DSYSCONFDIR=/etc																					\
		.. &&																								\
	#																										\
	$(MAKE)

mysql_package : fpm_install mysql_build
	mkdir -p $(WORKING_DIR)/mysql-$(MYSQL_VERSION)-install

	# Install MySQL into a directory suitable for turning into a package
	cd $(WORKING_DIR)/mysql-$(MYSQL_VERSION)/build &&						\
	$(MAKE) install INSTALL_ROOT=$(WORKING_DIR)/mysql-$(MYSQL_VERSION)-install

	# Set up the init.d files
	mkdir -p $(WORKING_DIR)/mysql-$(MYSQL_VERSION)-install/etc/init.d/
	cp $(WORKING_DIR)/mysql-$(MYSQL_VERSION)-install/usr/share/mysql/support-files/mysql.server $(WORKING_DIR)/mysql-$(MYSQL_VERSION)-install/etc/init.d/mysqld
	chmod 755 $(WORKING_DIR)/mysql-$(MYSQL_VERSION)-install/etc/init.d/mysqld

	# Generate the package
	mkdir -p $(GENERATED_PACKAGE_DIR) && cd $(GENERATED_PACKAGE_DIR) &&     \
	fpm -s dir -t deb -n mysql 												\
		-v $(MYSQL_VERSION) 												\
		-C $(WORKING_DIR)/mysql-$(MYSQL_VERSION)-install  					\
		-d libaio-dev 														\
		-d libncurses5-dev													\
		etc																	\
		usr/share/mysql

mysql_install : mysql_user gdebi_install
	### All this stuff should be handled by puppet
	gdebi -n $(GENERATED_PACKAGE_DIR)/mysql_$(MYSQL_VERSION)*.deb

	update-rc.d mysqld defaults

	# Set up the system tables
	chown -R mysql:mysql /usr/share/mysql
	cd /usr/share/mysql/ && scripts/mysql_install_db --user=mysql
	chown -R root /usr/share/mysql
	chown -R mysql /usr/share/mysql/data

	# Set up the MySQL config file
	cp /usr/share/mysql/support-files/my-default.cnf /etc/my.cnf

	# Start MySQL
	service mysqld start
