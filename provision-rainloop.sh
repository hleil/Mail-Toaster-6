#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA=""

mt6-include 'php'
mt6-include nginx

install_rainloop()
{
	install_php 56 || exit
	install_nginx || exit

	tell_status "installing rainloop"
	stage_pkg_install rainloop-community
}

configure_nginx_server()
{
	local _datadir="$ZFS_DATA_MNT/rainloop"
	if [ -f "$_datadir/etc/nginx-server.conf" ]; then
		tell_status "preserving /data/etc/nginx-server.conf"
		return
	fi

	tell_status "saving /data/etc/nginx-server.conf"
	tee "$_datadir/etc/nginx-server.conf" <<'EO_NGINX_SERVER'

server {
	listen       80;
	server_name  rainloop;

	set_real_ip_from haproxy;
	real_ip_header X-Forwarded-For;
	client_max_body_size 25m;

	location / {
		root   /usr/local/www/rainloop;
		index  index.php;
		try_files $uri $uri/ /index.php?$query_string;
	}

	error_page   500 502 503 504  /50x.html;
	location = /50x.html {
		root   /usr/local/www/nginx-dist;
	}

	location ~ \.php$ {
		root           /usr/local/www/rainloop;
		try_files $uri $uri/ /index.php?$query_string;
		fastcgi_split_path_info ^(.+\.php)(.*)$;
		fastcgi_keep_conn on;
		fastcgi_pass   127.0.0.1:9000;
		fastcgi_index  index.php;
		fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
		include        /usr/local/etc/nginx/fastcgi_params;
	}

	location ~ /\.ht {
		deny  all;
	}

	location ^~ /data {
		deny all;
	}
}

EO_NGINX_SERVER

	sed -i .bak \
		-e "s/haproxy/$(get_jail_ip haproxy)/" \
		"$_datadir/etc/nginx-server.conf"
}

install_default_ini()
{
	local _rlconfdir="$ZFS_DATA_MNT/rainloop/_data_/_default_"
	local _dini="$_rlconfdir/domains/default.ini"
	if [ -f "$_dini" ]; then
		tell_status "preserving default.ini"
		return
	fi

	if [ ! -d "$_rlconfdir/domains" ]; then
		tell_status "creating default/domains dir"
		mkdir -p "$_rlconfdir/domains" || exit
	fi

	tell_status "installing domains/default.ini"
	tee -a "$_dini" <<EO_INI
imap_host = "dovecot"
imap_port = 143
imap_secure = "None"
imap_short_login = Off
sieve_use = Off
sieve_allow_raw = Off
sieve_host = ""
sieve_port = 4190
sieve_secure = "None"
smtp_host = "haraka"
smtp_port = 587
smtp_secure = "TLS"
smtp_short_login = Off
smtp_auth = On
smtp_php_mail = Off
white_list = ""
EO_INI
}

set_default_path()
{
	local _rl_ver;
	_rl_ver="$(pkg -j stage info rainloop-community | grep Version | awk '{ print $3 }')"
	local _rl_root="$STAGE_MNT/usr/local/www/rainloop/rainloop/v/$_rl_ver"
	tee -a "$_rl_root/include.php" <<'EO_INCLUDE'

	function __get_custom_data_full_path()
	{
		return '/data/'; // custom data folder path
	}
EO_INCLUDE
}

configure_rainloop()
{
	configure_php rainloop
	configure_nginx rainloop
	configure_nginx_server

	# for persistent data storage
	chown 80:80 "$ZFS_DATA_MNT/rainloop/"

	set_default_path
	install_default_ini
}

start_rainloop()
{
	start_php_fpm
	start_nginx
}

test_rainloop()
{
	test_nginx
	test_php_fpm
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs rainloop
start_staged_jail
install_rainloop
configure_rainloop
start_rainloop
test_rainloop
promote_staged_jail rainloop