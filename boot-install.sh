#!/bin/bash

set -x

function generate_passwd {
   cat /dev/urandom | tr -dc "a-zA-Z0-9" | fold -w 15 | head -1
}

mkdir -p /data/etc/stunnel/
mkdir -p /data/etc/postfix/
mkdir -p /data/etc/httpd/
mkdir -p /data/etc/ssh/
mkdir -p /data/home
mkdir -p /data/lib
mkdir -p /data/etc/logrotate.d
mkdir -p /data/root && chmod 700 /data/root

pushd . > /dev/null
cd /var/lib
mv /var/lib/mysql /data/lib && ln -s /data/lib/mysql mysql
[ -d /var/lib/gitolite ] && mv /var/lib/gitolite /data/lib && ln -s /data/lib/gitolite gitolite
popd > /dev/null

# Apply tuleap patches (should be temporary until integrated upstream)
pushd . > /dev/null
cd /usr/share/tuleap
/bin/ls /root/app/patches/*.patch | while read patch; do
    patch -p1 -i $patch
done
popd > /dev/null

# Do not activate services
sed -ie 's/\$CHKCONFIG \$service on/: #\$CHKCONFIG \$service on/g' /usr/share/tuleap/tools/setup.sh
sed -ie 's/are stored.*/are stored in \/data\/root\/\.tuleap_passwd"/g' /usr/share/tuleap/tools/setup.sh

# Install Tuleap
/usr/share/tuleap/tools/setup.sh --disable-selinux --sys-default-domain=$SYS_DEFAULT_DOMAIN --sys-org-name=$ORG_NAME --sys-long-org-name=$ORG_NAME

# Setting root password
root_passwd=$(generate_passwd)
echo "root:$root_passwd" |chpasswd
echo "root: $root_passwd" >> /root/.tuleap_passwd

# Place for post install stuff
./boot-postinstall.sh

# Ensure system will be synchronized ASAP
/usr/share/tuleap/src/utils/php-launcher.sh /usr/share/tuleap/src/utils/launch_system_check.php

service mysqld stop
service httpd stop
service crond stop

# Postfix QQ SMTP SSL Tunnel
cat >> /etc/stunnel/stunnel.conf <<EoT
[smtps]
accept  = 11125
client = yes
connect = smtp.qq.com:465
EoT
#wget -O /etc/init.d/stunnel https://bugzilla.redhat.com/attachment.cgi?id=325164
chmod 755 /etc/init.d/stunnel
chkconfig --add stunnel
chkconfig stunnel on
service stunnel start

echo "[127.0.0.1]:11125  $RELAY_EMAIL:$RELAY_EMAIL_PASS" >> /etc/postfix/relay_creds
postmap hash:/etc/postfix/relay_creds
chmod go-rwx /etc/postfix/relay_creds*

echo "codendiadm $RELAY_EMAIL" >> /etc/postfix/canonical
postmap hash:/etc/postfix/canonical
chmod go-rwx /etc/postfix/canonical*

# Update Postfix config
perl -pi -e "s%^#myhostname = host.domain.tld%myhostname = $VIRTUAL_HOST%" /etc/postfix/main.cf
perl -pi -e "s%^alias_maps = hash:/etc/aliases%alias_maps = hash:/etc/aliases,hash:/etc/aliases.codendi%" /etc/postfix/main.cf
perl -pi -e "s%^alias_database = hash:/etc/aliases%alias_database = hash:/etc/aliases,hash:/etc/aliases.codendi%" /etc/postfix/main.cf
perl -pi -e "s%^#recipient_delimiter = %recipient_delimiter = %" /etc/postfix/main.cf

# Update php config
perl -pi -e "s%^short_open_tag = Off%short_open_tag = On%" /etc/php.ini
perl -pi -e "s%^;date.timezone =%date.timezone = Asia/Shanghai%" /etc/php.ini
perl -pi -e "s%^post_max_size = 8M%post_max_size = $PHP_POST_MAX_SIZE%" /etc/php.ini
perl -pi -e "s%^;default_charset = \"iso-8859-1\"%default_charset = \"utf-8\"%" /etc/php.ini
perl -pi -e "s%^upload_max_filesize = 2M%upload_max_filesize = $PHP_UPLOAD_MAX_FILESIZE%" /etc/php.ini
perl -pi -e "s%^;iconv.input_encoding = ISO-8859-1%iconv.input_encoding = UTF-8%" /etc/php.ini
perl -pi -e "s%^;iconv.internal_encoding = ISO-8859-1%iconv.internal_encoding = UTF-8%" /etc/php.ini
perl -pi -e "s%^;iconv.output_encoding = ISO-8859-1%iconv.output_encoding = UTF-8%" /etc/php.ini
perl -pi -e "s%^;intl.default_locale =%intl.default_locale = en_US.UTF-8%" /etc/php.ini
perl -pi -e "s%^;mbstring.language = Japanese%mbstring.language = Chinese%" /etc/php.ini
perl -pi -e "s%^;mbstring.internal_encoding = EUC-JP%mbstring.internal_encoding = UTF-8%" /etc/php.ini
perl -pi -e "s%^;mbstring.http_output = SJIS%mbstring.http_output = UTF-8%" /etc/php.ini
perl -pi -e "s%^;mbstring.encoding_translation = Off%mbstring.encoding_translation = On%" /etc/php.ini
perl -pi -e "s%^;mbstring.func_overload = 0%mbstring.func_overload = 6%" /etc/php.ini

# Update nscd config
perl -pi -e "s%enable-cache[\t ]+group[\t ]+yes%enable-cache group no%" /etc/nscd.conf

# Update mysql config
perl -pi -e "s%max_allowed_packet=128M%max_allowed_packet=$MYSQL_MAX_ALLOWED_PACKET%" /etc/my.cnf

perl -pi -e "s%\$sys_force_ssl[\t ]+=[\t ]+0%\$sys_force_ssl = $SYS_FORCE_SSL%" /etc/tuleap/conf/local.inc
perl -pi -e "s%\$sys_max_size_upload[\t ]+=[\t ]+67108864%\$sys_max_size_upload = $SYS_MAX_SIZE_UPLOAD%" /etc/tuleap/conf/local.inc
perl -pi -e "s%\$sys_max_size_attachment[\t ]+=[\t ]+16777216%\$sys_max_size_attachment = $SYS_MAX_SIZE_ATTACHEMENT%" /etc/tuleap/conf/local.inc

cat >> /etc/postfix/main.cf <<EoT

#added to enable SASL support for relayhost
relayhost = [127.0.0.1]:11125
smtp_sasl_type = cyrus
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/relay_creds
smtp_sasl_security_options = noanonymous
smtp_use_tls = yes
#smtp_cname_overrides_servername = no
#smtp_sasl_mechanism_filter = plain, login

canonical_maps = hash:/etc/postfix/canonical
#virtual_alias_maps = hash:/etc/postfix/virtual

# for Postfix ver >= 3.0
#smtp_tls_security_level = encrypt
#smtp_tls_wrappermode = yes
#smtp_generic_maps = hash:/etc/postfix/generic

EoT
service postfix reload

### Move all generated files to persistant storage ###

# Conf
#mv /etc/stunnel/stunnel.conf  /data/etc/stunnel
#mv /etc/postfix/main.cf       /data/etc/postfix
#mv /etc/postfix/relay_creds*  /data/etc/postfix
#mv /etc/postfix/canonical*    /data/etc/postfix
mv /etc/httpd/conf            /data/etc/httpd
mv /etc/httpd/conf.d          /data/etc/httpd
mv /etc/tuleap                /data/etc
mv /etc/aliases               /data/etc
mv /etc/logrotate.d/httpd     /data/etc/logrotate.d
mv /etc/libnss-mysql.cfg      /data/etc
mv /etc/libnss-mysql-root.cfg /data/etc
mv /etc/my.cnf                /data/etc
mv /etc/nsswitch.conf         /data/etc
mv /etc/crontab               /data/etc
mv /etc/passwd                /data/etc
mv /etc/shadow                /data/etc
mv /etc/group                 /data/etc
mv /root/.tuleap_passwd       /data/root
mv /etc/ssh/ssh_host_*        /data/etc/ssh

# Data
mv /home/codendiadm /data/home
mv /home/groups    /data/home
mv /home/users     /data/home
mv /var/lib/tuleap /data/lib

# Will be restored by boot-fixpath.sh later
[ -h /var/lib/mysql ] && rm /var/lib/mysql
[ -h /var/lib/gitolite ] && rm /var/lib/gitolite
