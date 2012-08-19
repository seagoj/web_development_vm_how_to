# BUILD A NEW DEVELOPMENT VIRTUAL MACHINE 
The goal here is to build a development virtual machine that can support PHP web development.  While I'm aiming to keep this as generally usable as possible, there are places where I install specific tools or configure them specifically to support my projects.  Be aware that there will need to be some improvization on your part along the way if you want this to work for you.

The basic features of this environment are:
- [Minimal Ubuntu 12.04 Server](https://help.ubuntu.com/community/Installation/MinimalCD) as a [VirtualBox](https://www.virtualbox.org/) guest
 - [Windows 7](http://windows.microsoft.com/en-US/windows7/products/home) Host (but don't let that turn you away in disgust, it matters very little)
 - Shared directory between the host and guest for code development
 - Firewall configured with [UFW](https://wiki.ubuntu.com/UncomplicatedFirewall?action=show&redirect=UbuntuFirewall)
- [PHP 5.4.5](http://www.php.net/), compiled from source
 - FastCGI with [PHP-FPM](http://php-fpm.org/), including Unix socket configuration for talking to Nginx
 - [APC](http://php.net/manual/en/book.apc.php), built from [PECL](http://pecl.php.net/)
- [Nginx 1.2.2](http://nginx.org/), compiled from Source
- [MySQL 5.5](http://dev.mysql.com/doc/refman/5.5/en/), installed from Ubuntu's package repository
- [SASS](http://sass-lang.com/) and [Compass](http://compass-style.org/), for developing CSS
- [YUI Compressor](http://developer.yahoo.com/yui/compressor/), for compressing web assets

## ON THE HOST
### Create the guest
- Install VirtualBox: https://www.virtualbox.org/wiki/Downloads
- Configure the host-only network:
 - Start up the VirtualBox Manager
 - Go to `File` -> `Preferences...` -> `Network`
 - Ensure the existence of (or create) a Host-Only Network with these properties:
  - Named `VirtualBox Host-Only Ethernet Adapter`
  - IPv4 Address `192.168.56.1`
  - IPv4 Network Mask `255.255.255.0`
  - Disabled DHCP Server
- Download the Ubuntu 12.04 server minimal ISO from https://help.ubuntu.com/community/Installation/MinimalCD/#A64-bit_PC_.28amd64.2C_x86_64.29
- Edit the attached ```create_new_vm.bat``` script and supply reasonable configuration values.  
- From the Windows CLI, run the ```create_new_bm.bat``` batch script with a chosen new Virtual Machine name to create the new virtual machine:
```
create_new_vm.bat SomeNewVMName                   
```

 - This just sets up a new VM, disk, mounts the ubuntu iso and starts the VM
 - Two NICs, one set up for host-only the other one for NAT (see script for details)
 - One shared directory, named 'shared_workspace', from 'E:\Users\jhanson\shared_workspace'
  
- start the virtual machine with:
```
vboxmanage startvm SomeNewVMName
```

- Follow all the onscreen Ubuntu setup, mostly accepting defaults.  When it comes to selecting packages, select only the OpenSSH server.
- Choose an IP address for the guest (I chose `192.168.56.11` below) and set up the Windows hosts file by editing `C:\Windows\System32\drivers\etc\hosts` and adding (note these domains are specific to my configuration):
```
# Development VM
192.168.56.11          jonathan-hanson.local
192.168.56.11          www.jonathan-hanson.local
192.168.56.11          beer.jonathan-hanson.local
192.168.56.11          gas.jonathan-hanson.local
```

- At this point it might be worth while to create a backup of the guest's virtual disk to enable future cloning and rollbacks.  See the VirtualBox Manager for details on how to do this.


## ON THE GUEST
Until the network interfaces are set up correctly, you'll need to do this part from the VirtualBox guest directly (that is, not over SSH).

### Set up the network interfaces
- Noted from `ifconfig` that the `eth0` and `lo` adapters are present but `eth1` isn't.  Did `ifconfig eth1 up` and it came up, but with only an ipv6 address.
- Both adapters were configured for DHCP, but the virtualbox host-only DHCP server is disabled (see above).
- Set up `eth1` with a static IP by adding this to `/etc/network/interfaces`:
```
# The host-only virtualbox interface
auto eth1
iface eth1 inet static
address 192.168.56.11
netmask 255.255.255.0
network 192.168.56.0
broadcast 192.168.56.255
```

- Reboot the machine and verify that `ifconfig` now shows `eth1` with the ip address chosen above.  Instead of rebooting, we could probably do `sudo service networking restart` but didn't test that.)
- At this point you should be able to ssh into the the guest from the host using the IP address chosen above (in my case, `192.168.56.11`).  On subsequent VM startups you should be able to start it headless with:
``` bash
vboxmanage startvm SomeVMName --type=headless
```

### Set up firewall
``` bash
sudo ufw default deny
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow 443
sudo ufw enable
```


### Add VirtualBox shared mount
``` bash
sudo mkdir /media/sf_shared_workspace
```

- Configure the mount by adding to `/etc/fstab`:
```
# virtualbox shared workspace, owned by www-data:www-data
shared_workspace     /media/sf_shared_workspace vboxsf     defaults,uid=33,gid=33     0     0
```

- Mount the shared disk
``` bash
sudo mount /media/sf_shared_workspace
```


### install nginx
- Fetch, make, and install:
``` bash
sudo apt-get install libc6 libpcre3 libpcre3-dev libpcrecpp0 libssl0.9.8 libssl-dev zlib1g zlib1g-dev lsb-base
wget http://nginx.org/download/nginx-1.2.2.tar.gz
tar -xvf nginx-1.2.2.tar.gz
cd nginx-1.2.2
./configure --prefix=/usr --sbin-path=/usr/sbin --pid-path=/var/run/nginx.pid --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --user=www-data --group=www-data --with-http_ssl_module
make
sudo make install
```

- Install the init script (TODO I need to actually source this with wget from somewhere.)
``` bash
cp nginx /etc/init.d/
sudo chmod 755 /etc/init.d/nginx
sudo update-rc.d nginx defaults
```

- Create the nginx default log directory
``` bash
sudo mkdir /var/log/nginx
```

- Install the nginx config files (these are specific to the sites I'm developing. TODO source nginx.conf and the sites-available directory from somewhere safe):
``` bash
sudo mkdir /etc/nginx/sites-available
sudo mkdir /etc/nginx/sites-enabled
cp nginx.conf /etc/nginx/
cp sites-available/* /etc/nginx/sites-available/*
ln -s /etc/nginx/sites-available/catchall /etc/nginx/sites-enabled/catchall
ln -s /etc/nginx/sites-available/groundhog /etc/nginx/sites-enabled/groundhog
```

- start nginx
``` bash
sudo service nginx start
```


### install php
- Fetch, make, and install:
``` bash
sudo apt-get install autoconf libxml2 libxml2-dev libcurl3 libcurl4-gnutls-dev libmagic-dev
wget http://us3.php.net/get/php-5.4.5.tar.bz2/from/us2.php.net/mirror -O php-5.4.5.tar.bz2
tar -xvf php-5.4.5.tar.bz2
cd php-5.4.5
./configure --prefix=/usr --sysconfdir=/etc --with-config-file-path=/etc --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --enable-mbstring --with-mysqli
make
sudo make install
```

- Copy the generated ini file to the config directory:
``` bash
sudo cp php.ini-production /etc/php.ini
```

- Copy over the PHP-FPM config file:
``` bash
sudo cp /etc/php-fpm.conf.default /etc/php-fpm.conf
```

 Note that this file has been modified after it was copied:
 - uncommented the pid directive: `pid = run/php-fpm.pid`
 - set the error log location to `/var/log/php-fpm/php-fpm.log`
 - changed the listen location: `listen = /tmp/php.socket`

- Create the php-fpm log file:
``` bash
sudo mkdir /var/log/php-fpm
```

- Install the PHP init script:
``` bash
sudo cp sapi/fpm/init.d.php-fpm /etc/init.d/php-fpm
sudo chmod 755 /etc/init.d/php-fpm
sudo update-rc.d php-fpm defaults
```

- Install the APC and HTTP extensions:
``` bash
sudo pecl update-channels
sudo pecl install pecl_http apc-beta (answer with defaults)
```

 NOTE that `apc-beta` was necessary above to get APC version 3.1.11 (in beta right now) which includes fixes for PHP 5.4 compatability.  This may not be necessary down the road, so keep an eye on it.  The production package name is `apc`.

 append to `/etc/php.ini`:
 ```
 extension=http.so
 extension=apc.so
 ```


- start php-fpm:
``` bash
sudo service php-fpm start
```


### MYSQL
- Install:
 DON'T DO THIS (because I'm not building from scratch just yet):
``` bash
sudo apt-get install cmake
wget http://dev.mysql.com/get/Downloads/MySQL-5.5/mysql-5.5.25a.tar.gz/from/http://cdn.mysql.com/ -O mysql-5.5.25a.tar.gz
tar -xvf mysql-5.5.25a.tar.gz
cd mysql-5.5.25a
```

 Instead do this: (because screw it, I'm cheating on this one and using `apt-get`.  Building MySQL from source looks like a pain in the ass with no gain):
 ``` bash
 sudo apt-get install mysql-server-5.5  
 ```


### set up development code symbolic link
``` bash
sudo ln -s /media/sf_shared_workspace /var/www
```


### Install Compass/Sass
``` bash
sudo apt-get install ruby1.9.3
sudo gem update
sudo gem install compass
sudo ln -s /usr/local/bin/compass /usr/bin/compass
```


### Install YUI Compressor
- Install java runtime (required for yui compressor):
``` bash
sudo apt-get install default-jre
```

- Fetch and install the `yui-compressor` jar file
``` bash
sudo apt-get install unzip
wget http://yui.zenfs.com/releases/yuicompressor/yuicompressor-2.4.7.zip
unzip yuicompressor-2.4.7.zip
sudo mkdir /usr/share/yui-compressor
sudo cp yuicompressor-2.4.7/build/yuicompressor-2.4.7.jar /usr/share/yui-compressor/yui-compressor.jar
```

### Install Git (used by composer.phar)
``` bash
sudo apt-get install git
```


# UPDATING
Periodically it'll be necessary to upgrade this machine without rebuilding it.  Here's how:
- Apt Repository update (covers MySQL): 
 ``` bash
 sudo apt-get update; sudo apt-get dist-upgrade;
 ```
- php -- make clean and recompile as during the install above
- nginx -- make clean and recompile as during the install above
- Ruby Gem update for Compass and SASS:
 ``` bash 
 sudo gem update
 ```  
- YUI-compressor - redownload and overwrite the jar file, as during the install above


# TODO
- mysql config
- phpmyadmin
- SSL cert
- IPv6?
- on server errors, nginx just throws ugly 500 response
- scriptify everything
- project code git pull (this isn't actually necessary for VM dev machines, but I should research it for building in production)
- Come up with the production server variant of all this (should be similar)


# NOTES
- http://wiki.nginx.org/Configuration
- http://www.howtoforge.com/installing-php-5.3-nginx-and-php-fpm-on-ubuntu-debian