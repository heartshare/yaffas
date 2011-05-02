Name:		yaffas-zarafa
Version: 0.7.0
Release: 1
Summary:	configure yaffas for zarafa
Group:		Application/System
License:	AGPL
URL:		http://www.yaffas.org
Source0:	file://%{name}-%{version}.tar.gz
BuildRoot:	%(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
BuildArch:  noarch
Requires:	php, php-cli, php-ldap, mysql-server, zarafa-webaccess, zarafa, z-push, yaffas-module-zarafalicence, yaffas-module-zarafaresources, yaffas-module-zarafaconf, yaffas-module-changelang, yaffas-module-zarafabackup, mod_ssl

%description
Additional yaffas configuration to make zarafa work

%build
make %{?_smp_mflags}

%install
%{__rm} -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

%clean
%{__rm} -rf $RPM_BUILD_ROOT

%post
YAFFAS_EXAMPLE=/opt/yaffas/share/doc/example
for CFG in /etc/zarafa/*.cfg; do
	%{__cp} -f $CFG ${CFG}.yaffassave
done
%{__cp} -f -a ${YAFFAS_EXAMPLE}/etc/zarafa/*.cfg /etc/zarafa

# PHPINI=/etc/php5/apache2/php.ini
# PHPCLIINI=/etc/php5/cli/php.ini
LDAPHOSTNAME=`grep "BASEDN=" /etc/ldap.settings | cut -d= -f2-`
# LIC="/etc/zarafa/license/base"
# chmod 600 /etc/zarafa/server.cfg
# chmod 600 /etc/zarafa/ldap.cfg
# chmod 600 /etc/zarafa/ldap.yaffas.cfg
# #necessary if zarafa installed after first installation
# /usr/sbin/locale-gen

export PERLLIB="/opt/yaffas/lib/perl5"
perl -MYaffas::Module::ChangeLang -wle '
my $lang = Yaffas::Module::ChangeLang::get_lang();
Yaffas::Module::ChangeLang::set_lang($lang);
'
# 
# 
# if ! grep ldap.so $PHPINI; then
# 	echo "extension = ldap.so" >> $PHPINI
# fi
# if ! grep mapi.so $PHPINI; then
# 	echo "extension = mapi.so" >> $PHPINI
# fi
# if ! grep mapi.so $PHPCLIINI; then
# 	echo "extension = mapi.so" >> $PHPCLIINI
# fi
# sed 's/^magic_quotes_gpc[[:space:]]*=.*/magic_quotes_gpc = Off/' -i $PHPINI
# sed 's/^memory_limit[[:space:]]*=[[:space:]]*16M/memory_limit = 64M/' -i $PHPINI
# 
# a2enmod proxy
# a2enmod ssl
# a2ensite zarafa-webaccess-ssl
sed "s/LDAPHOSTNAME/$LDAPHOSTNAME/g" -i /etc/zarafa/ldap.yaffas.cfg
# 
# #if ! grep "Listen.*443" /etc/apache2/ports.conf &>/dev/null; then
# #	echo "Listen 443" >> /etc/apache2/ports.conf
# #fi
# 
# sed -e 's/DAGENT_ENABLED=no/DAGENT_ENABLED=yes/' -i /etc/default/zarafa-dagent
# 

SSL_CONF=/etc/httpd/conf.d/ssl.conf
if [ -e $SSL_CONF ]; then
	sed -e 's#^SSLCertificateFile.*#SSLCertificateFile /opt/yaffas/etc/ssl/certs/zarafa-webaccess.crt#' -i $SSL_CONF
	sed -e 's#^SSLCertificateKeyFile.*#SSLCertificateKeyFile /opt/yaffas/etc/ssl/certs/zarafa-webaccess.key#' -i $SSL_CONF
fi

# optimize memory
if [ "$1" = 1 ]; then
	# only on a fresh installation
	MEM=$(cat /proc/meminfo | awk '/MemTotal:/ { printf "%d", $2*0.25*1024 }')
	echo -e "[mysqld]\ninnodb_buffer_pool_size = $MEM\ninnodb_log_file_size = $((MEM/4))\n innodb_log_buffer_size = $((MEM/16))" >> /etc/my.cnf
	%{__rm} -f /data/db/mysql/ib_logfile* /var/lib/mysql/ib_logfile*
	sed -e 's/^cache_cell_size.*/cache_cell_size = '$MEM'/' -i /etc/zarafa/server.cfg
 
	%{__mkdir} -p /data/zarafa/attachments/
fi

##EVIL!!
#set +e
#service mysqld start
#service ldap start
#service zarafa-server start
#service zarafa-dagent restart
#service httpd restart

if [ "$1" = 1 ] ; then
	#only do this on install, not on upgrade
	zarafa-admin -s
fi

# register product
CONF="/opt/yaffas/etc/installed-products"
KEY="zarafa"
VALUE='yaffas|ZARAFA'

if ZARAFAVERSION=$(/bin/rpm -q --qf %{VERSION} zarafa); then
	VALUE="yaffas|ZARAFA v$ZARAFAVERSION"
fi
if [ -e $CONF ]; then
	if ! grep -iq ^$KEY $CONF; then
		echo "$KEY=$VALUE" >> $CONF
	else
		sed -e s/^$KEY=.*/"$KEY=$VALUE"/ -i $CONF
	fi
else
	echo "$KEY=$VALUE" >> $CONF
fi

# install zarafa selinux module
if [ "$1" = 1 ] ; then
	checkmodule -M -m -o /tmp/zarafa.mod /tmp/zarafa.te
	semodule_package -o /tmp/zarafa.pp -m /tmp/zarafa.mod
	semodule -i /tmp/zarafa.pp
fi
%{__rm} -f /etc/zarafa/ldap.yaffas.cfg
%{__rm} -f /tmp/zarafa.{pp,mod,te}

%postun
for CFG in /etc/zarafa/*.cfg.yaffassave; do
	%{__mv} -f $CFG ${CFG/.yaffassave/}
done

%files
%defattr(-,root,root,-)
%doc debian/{changelog,copyright}
%config /opt/yaffas/share/doc/example/etc/zarafa/dagent.cfg
%config /opt/yaffas/share/doc/example/etc/zarafa/gateway.cfg
%config /opt/yaffas/share/doc/example/etc/zarafa/ical.cfg
%config /opt/yaffas/share/doc/example/etc/zarafa/ldap.yaffas.cfg
%config /opt/yaffas/share/doc/example/etc/zarafa/ldap.cfg
%config /opt/yaffas/share/doc/example/etc/zarafa/monitor.cfg
%config /opt/yaffas/share/doc/example/etc/zarafa/server.cfg
%config /opt/yaffas/share/doc/example/etc/zarafa/spooler.cfg
/tmp/zarafa.te

%changelog
* Mon Mar 08 2011 Package Builder <packages@yaffas.org> 0.7.0-1
- initial release
