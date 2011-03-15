#!/usr/bin/perl -w
my @ldap_conffiles = ("/etc/pam_ldap.conf", "/etc/libnss-ldap.conf", "/etc/ldap/slapd.conf", "/etc/ldap/ldap.conf", "/etc/smbldap-tools/smbldap.conf", "/etc/samba/smb.conf", "/etc/smbldap-tools/smbldap_bind.conf", "/var/lib/opengroupware.org/.libFoundation/Defaults/NSGlobalDomain.plist", "/etc/zarafa/ldap.cfg", "/etc/zarafa/ldap.bitkit.cfg", "/etc/ldap.settings", "/etc/ldap.conf");
my @other_conffiles = ("/etc/hosts", "/etc/defaultdomain");
my $old_domain;
my $old_org;
my $new_domain;
my $new_org;
my $ldif_file = "";

sub usage() {
	print "Usage: domrename.pl <old domain> <new domain> [<ldif file>]\n";
	print "Note: if <ldif file> is specified only /tmp/slapcat.ldif will be changed\n";
	exit(-1);
}

if (defined($ARGV[0]) && ! defined($ARGV[1])) {
	usage();
} elsif (defined($ARGV[0]) && defined($ARGV[1]) && ! defined($ARGV[2])) {
	$old_domain = $ARGV[0];
	$new_domain = $ARGV[1];
} elsif (defined($ARGV[0]) && defined($ARGV[1]) && defined($ARGV[2])) {
	$old_domain = $ARGV[0];
	$new_domain = $ARGV[1];
	$ldif_file = $ARGV[2];
} else {
	usage();
}

$ldap_old_domain = getLDAPDomain($old_domain);
$ldap_new_domain = getLDAPDomain($new_domain);

my @file;
if ($ldif_file eq "") {
	# LDAP config files
	foreach $_ (@ldap_conffiles) {
		if (-r $_) {
			open FILE, $_ or die "Couldn't open file $_";
			@file = <FILE>;
			print "Processing $_ ...\n";
			@file = replaceString($ldap_old_domain, $ldap_new_domain, @file);
			close FILE;

			open OUTFILE, "> $_" or die "Couldn't open file /tmp/$_";
			print OUTFILE @file;
		} else {
			print "Couldn't read $_\n";
		}
	}
	
	# Other config files
	foreach $_ (@other_conffiles) {
		if (-r $_) {
			open FILE, $_ or die "Couldn't open file $_";
			@file = <FILE>;
			print "Processing $_ ...\n";
			@file = replaceString($old_domain, $new_domain, @file);
			close FILE;

			open OUTFILE, "> $_" or die "Couldn't open file /tmp/$_";
			print OUTFILE @file;
		} else {
			print "Couldn't read $_\n";
		}
	}
}

if ($ldif_file eq "") {
	print "Processing slapcat ...\n";
	@ldif = `slapcat`;
} else {
	print "Opening file $ldif_file ...\n";
	open LDIF, "< $ldif_file" or die "Couldn't open file $ldif_file";
	@ldif = <LDIF>;
	close LDIF;
}

@ldif = replaceString($ldap_old_domain, $ldap_new_domain, @ldif);
@ldif = correctLDIF($ldap_new_domain, @ldif);

open OUTFILE, "> /tmp/slapcat.ldif";
print OUTFILE @ldif;
close OUTFILE;

if ($ldif_file eq "") {
	print "Stopping slapd ...\n";
	`/etc/init.d/slapd stop`;
	`rm -rf /var/lib/ldap/*`;

	print "Executing slapadd ...\n";
	`slapadd -vl /tmp/slapcat.ldif`;
	`chown -R openldap:openldap /var/lib/ldap/`;
	print "Starting slapd ...\n";
	`/etc/init.d/slapd start`;

	print "Restarting nscd ...\n";
	`/etc/init.d/nscd restart`;

	if (-x "/etc/init.d/opengroupware.org.org") {
		print "Restarting opengroupware.org ...\n";
		`/etc/init.d/opengroupware.org restart`;
	}

	open LDAP, "< /etc/ldap.secret";
	@ldap = <LDAP>;
	chomp($ldap[0]);
	`smbpasswd -w $ldap[0]`;
}

print "done\n";


# replaceString("oldstring", "newstring", textarray)
sub replaceString {
	my ($od, $nd, @array) = @_;
	my @newarray;

	foreach $_ (@array) {
		$_ =~ s/$od/$nd/g;
		push(@newarray, $_);
	}
	return @newarray;
}

# getLDAPDomain("domainstring")
sub getLDAPDomain {
	if ($_[0] eq "BASE") {
		return "BASE";
	}
	my @tmp = split(/\./, $_[0]);
	die "Domain $_[0] too short" if ($#tmp < 1 && $_[0] ne "BASE");
	my $new;
	my $org;

	for($i=0; $i<=$#tmp; $i++) {
		if ($i == $#tmp) {
			$new .= "c=".$tmp[$i];
		} elsif ($i == $#tmp-1) {
			$new .= "o=".$tmp[$i];
			$org = $tmp[$i];
		} else {
			$new .= "ou=".$tmp[$i];
		}
		$new .= "," if ($i != $#tmp);
	}

	return $new;
}

sub correctLDIF {
	my ($nd, @ldif) = @_;

	for ($i=0; $i<$#ldif; $i++) {
		last if ($ldif[$i] =~ /^$/);
		$ldif[$i] = "";
	}
	@tmp = split (/,/, $nd);
	@tmp = split (/=/, $tmp[0]);
	
	if ($tmp[0] eq "o") {
		unshift (@ldif, "dn: ".$nd."\n", "o: $tmp[1]\n", "objectClass: top\n", "objectClass: organization\n");
	} else {
		unshift (@ldif, "dn: ".$nd."\n", "ou: $tmp[1]\n", "objectClass: top\n", "objectClass: organizationalUnit\n");
	}

	return @ldif;
}

