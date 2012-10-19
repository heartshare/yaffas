#!/bin/bash

# this is an update :)

if ! grep "^tls_checkpeer" $CONF > /dev/null; then
	echo "tls_checkpeer no" >> $CONF
fi

if ! grep zarafa.schema $SLAPD &>/dev/null; then
	sed 's|include[[:space:]]\+/etc/openldap/schema/samba.schema|include\t/etc/openldap/schema/samba.schema\ninclude /etc/openldap/schema/zarafa.schema|' -i $SLAPD
fi

if grep -q 'BASEDN.*o=.*c=' /etc/ldap.settings; then
	echo "fixing ldap dn..."
	/opt/yaffas/bin/domrename.pl $DOMAIN $DOMAIN upgrade
	service zarafa-server restart
	service postfix reload
	service smb restart
fi