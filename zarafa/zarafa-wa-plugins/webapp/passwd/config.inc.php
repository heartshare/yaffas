<?php
// configuration file for passwd plugin

// this is handled in php/plugin.passwd.php
define("PLUGIN_PASSWD_USER_DEFAULT_ENABLE", true);

class PluginpasswdConfiguration
{
	// select authentication method: ldap, ad, passwd (see php/pwdchange.php)
	private $method = "ldap";

	// basedn, to search for users dn
	private $basedn = "dc=bitbone,dc=de";

	// ldap server uri
	// examples: "ldapi:///" or "localhost" or "127.0.0.1"
	private $uri = "localhost";

	function get_basedn () {
		return $this->basedn;
	}

	function get_uri () {
		return $this->uri;
	}

	function get_method () {
		return $this->method;
	}

}
/*
	vim:ts=2:sw=2:noet:
*/
?>
