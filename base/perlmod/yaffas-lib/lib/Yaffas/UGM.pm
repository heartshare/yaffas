#!/usr/bin/perl
package Yaffas::UGM;

use warnings;
use strict;

sub BEGIN {
	use Exporter;
	our @ISA= qw(Exporter);
	our @EXPORT_OK = qw(get_users
						get_groups
						group_exists
						add_group
						get_groups_name
						rm_group
						gecos
						name
						get_uid_by_username
						get_username_by_uid
						get_suppl_groupnames
						get_email
						is_user_in_group
						get_system_users
						del_email
						get_print_operators_group
						set_print_operators_group);
}

use Yaffas::LDAP;
use Yaffas::Check;
use Yaffas::Exception;
use Yaffas qw(do_back_quote);
use Error qw(:try);
use Yaffas::Constant;
use Yaffas::Mail;
use Yaffas::Mail::Mailalias;
use Yaffas::File;
use Yaffas::File::Config;
use Yaffas::Postgres;
use Text::Iconv;
use File::Path;
use File::Samba;
use File::Copy;
use Yaffas::Auth;
use Yaffas::Auth::Type qw(:standard);
use Yaffas::Service qw(control START STOP RESTART HYLAFAX);


### prototypes ###
sub rm_group($);
sub add_group($);
sub add_user($$$$@);
sub del_email($);
sub gecos($;$$);
sub get_user_entries(;$);
sub get_users(;$);
sub get_users_full;
sub get_groups ();
sub get_all_groups_name ();
sub get_groupname_by_gid($);
sub get_gid_by_groupname($);
sub get_suppl_groupnames($);
sub get_suppl_groupids($);
sub get_email($);
sub is_user_in_group ($$);
sub password($$);
sub user_exists($);
sub group_exists($);
sub get_crypted_passwd($);
sub rm_user ($);
sub mod_group_ftype(%);
sub mod_user_ftype(%);
sub get_hylafax_filetype ($$);
sub get_print_operators_group();
sub set_print_operators_group($;$$);
sub _get_workgroup();

{
	my $getent;
	my $getent_cmd = Yaffas::Constant::APPLICATION->{getent};
	sub getent{
		unless(defined $getent) {
			my @passwd  = `$getent_cmd passwd`;
			my @group = `$getent_cmd group`;

			my %pw_data_name;
			my %pw_data_uid;
			foreach(@passwd){
				my  ($username, undef,$uid, $gid) = split(/:/, $_);
				$pw_data_name{$username} = $_;
			}
			$getent = {
				passwd => \@passwd,
				group => \@group,
				passwd_data_name => \%pw_data_name,
			};

		}
		if(exists $getent->{$_[0]}){
			return $getent->{$_[0]}
		}else{
			return undef;
		}
	}
	sub clear_cache {
		undef $getent;
	}
	sub add_user_to_cache {
		my $user = shift;
		my $line = `$getent_cmd passwd $user`;
		push @{ $getent->{passwd} }, $line;
	}
	sub add_group_to_cache {
		my $group = shift;
		my $line = `$getent_cmd group $group`;
		push @{ $getent->{group} }, $line;
	}
}
=pod

=head1 NAME

Yaffas::UGM - Functions for Group and User Managment

=head1 SYNOPSIS

use Yaffas::UGM

=head1 DESCRIPTION

Yaffas::UGM provieds fuctions for User and Group Managment.

=head1 FUNCTIONS

=over

=item rm_group ( GROUP )

Deletes group GROUP. On success returns 1 otherwise throws exception

=cut

sub rm_group($) {
	my $group = shift;
	Yaffas::Exception->throw('err_no_local_auth')
	  unless ( Yaffas::Auth::auth_type eq Yaffas::Auth::Type::LOCAL_LDAP
		|| Yaffas::Auth::auth_type eq Yaffas::Auth::Type::FILES );
	throw Yaffas::Exception('err_undeletable_group',$group) if grep {$group eq $_} @{Yaffas::Constant::MISC->{admin_groups}};
	system(Yaffas::Constant::APPLICATION->{groupdel}, $group);
	throw Yaffas::Exception('err_del_group') unless ($? == 0);
	try {
		clean_group_data($group);
	}
	catch Yaffas::Exception with {
		shift()->throw();
	};


	return 1;
}

=item clean_group_data ( GROUP )

Cleans group related data

return 1 on success, exception on error

=cut

sub clean_group_data($) {
	my $group = shift;
	try {
		if (Yaffas::Product::check_product('fax'))
		{
			my $dbh = Yaffas::Postgres::connect_db("bbfaxconf") ;

			# get id of group
			my $sqlq = "select id from ug where ug = '$group' and type = 'g'";
			my @tmp = Yaffas::Postgres::search_entry_rows($dbh, $sqlq);
			my $id = $tmp[0][0];

			if (defined ($id))
			{
				# delete ft of gid
				$sqlq = "delete from ft where id = $id";
				Yaffas::Postgres::del_entry($dbh, $sqlq);

				# delete msn(s) of gid
				if (Yaffas::Check::faxtype eq "AVM")
				{
					$sqlq = "delete from msn_avm where id = $id";
				}
				else
				{
					$sqlq = "delete from msn_eicon where id = $id";
				}
				Yaffas::Postgres::del_entry($dbh, $sqlq);

				# delete gid
				$sqlq = "delete from ug where id = $id";
				Yaffas::Postgres::del_entry($dbh, $sqlq);
			}
			Yaffas::Postgres::pg_disconnect($dbh);
		}
		return 1;
	}
	catch Yaffas::Exception with {
		shift()->throw();
	};
}


=item add_group ( GROUP )

Adds group GROUP to system. On success returns 1 else C<undef>.

=cut

sub add_group($) {
	my $group = shift;
	do_back_quote(Yaffas::Constant::APPLICATION->{groupadd}, "-a", $group);
 	throw Yaffas::Exception('err_add_group') unless ($? == 0);
	add_group_to_cache( $group );
	return 1;
}

=item add_user( USERNAME, EMAIL, GECOS, GROUPS )

Adds a user with USERNAME, GROUPS, EMAIL and GECOS entry to userdatabase.

=cut

sub add_user($$$$@) {
	my $login = shift;
	my $email = shift;
	my $givenname = shift;
	my $surname = shift;
	my @groups = @_;
	my $shell = '/bin/false';
	my $ret = undef;

	my $gecos = _fix_gecos("$givenname $surname");

	my $success = undef;
	#my $pgid = get_group_id('bkusers');
	my $pgid = "500";

	my $bke = Yaffas::Exception->new();

	Yaffas::Exception->throw('err_no_local_auth')
	  unless ( Yaffas::Auth::auth_type eq Yaffas::Auth::Type::LOCAL_LDAP
		|| Yaffas::Auth::auth_type eq Yaffas::Auth::Type::FILES );

	unless (Yaffas::Check::username($login)) {
		$bke->add('err_username', $login);
	}

	if (grep {$login eq $_} Yaffas::UGM::get_system_users ()
	    || grep {$login eq $_} Yaffas::Constant::MISC->{'never_users'}) {
		$bke->add ('err_never_user');
	}

	for (@groups) {
		unless (Yaffas::Check::groupname($_)) {
			$bke->add('err_groupname', $_);
		}
	}

	unless (Yaffas::Check::gecos($givenname) && Yaffas::Check::gecos($surname)) {
		$bke->add('err_gecos', $login);
	}

	if ($email) {
		unless (Yaffas::Check::email($email)) {
			$bke->add('err_email', $login);
		}
	}

	my $gid = join ",", @groups;

	my @cmd;
	push @cmd, Yaffas::Constant::APPLICATION->{useradd}, "-g", $pgid;
	push @cmd, "-G", $gid;
	push @cmd, "-m", "-a";
	push @cmd, "-s", $shell;

	push @cmd, "-c", $gecos;
	push @cmd, "-N", $givenname;
	push @cmd, "-S", $surname;
	push @cmd, $login;


	# existiert der benutzer bereits?
	if (user_exists( $login )) {
		$bke->add('err_user_exists_allready');
	}

	throw $bke if $bke;

	# is there an alias already with the same name?
	my $alias = Yaffas::Mail::Mailalias->new();
	if ($alias->get_alias_destination($login)) {
		throw Yaffas::Exception('err_name_is_alias', $login);
	}

	my $ret_text = do_back_quote(@cmd);
	if ($? == 0) {
		$success = 1;

		$ret = Yaffas::LDAP::add_entry($login, "objectClass", "zarafa-user");
		if ($ret != 0) {
			$success = undef;
		}
		$ret = Yaffas::LDAP::add_entry($login, "zarafaAccount", "1");
		if ($ret != 0) {
			$success = undef;
		}
		$ret = Yaffas::LDAP::del_entry($login, 'sambaPwdMustChange');
		if ($ret != 0) {
			$success = undef;
		}

		if ( $success and length($email) > 0 ) {
			$ret += Yaffas::LDAP::replace_entry($login, "mail", $email);

			if ($ret != 0) {
				$success = undef;
			}
		}
		name($login, $givenname, $surname);

		rm_user($login) unless $success;
		throw Yaffas::Exception("err_LDAP_failed", $ret) unless ($success);
	}
	throw Yaffas::Exception("err_useradd_failed", $ret_text) unless $success;

	# add user in cache.
	add_user_to_cache($login);

	# add user's groups in cache
	clear_cache();
	getent();

	return $success;
}

=item rm_user ( USERNAME|UID )

Removes user with USERNAME or UID from database

=cut

sub rm_user ($) {
	my $login = shift;
	my $ret = undef;

	Yaffas::Exception->throw('err_no_local_auth')
	  unless ( Yaffas::Auth::auth_type eq Yaffas::Auth::Type::LOCAL_LDAP
		|| Yaffas::Auth::auth_type eq Yaffas::Auth::Type::FILES );

	if ($login =~ /^\d+$/) 
	{
		$login = get_username_by_uid($login);
	}
	unless (user_exists($login)) 
	{
		Yaffas::Exception->throw('err_user_doesnt_exist');
	}

	system(Yaffas::Constant::APPLICATION->{userdel}, "-r", $login);
	unless ($? == 0) 
	{
		Yaffas::Exception->throw("err_del_user" , $! );
	}

	if (Yaffas::Product::check_product("zarafa")) {
		system(Yaffas::Constant::APPLICATION->{zarafa_admin}, "--sync");
	}
	unless ($? == 0) 
	{
		Yaffas::Exception->throw("err_del_user" , $! );
	}

	try {
		clean_user_data($login);
	}
	catch Yaffas::Exception with {
		shift()->throw();
	};
}

=item clean_user_data ( USERNAME )

Cleans user related data

return 1 on success, exception on error

=cut

sub clean_user_data ($) {
	my $login = shift;
	try {
		if (Yaffas::Product::check_product('fax'))
		{
			my $dbh = Yaffas::Postgres::connect_db("bbfaxconf");
			# get id of user 
			my $sqlq = "select id from ug where ug = '$login' and type = 'u'";
			my @tmp = Yaffas::Postgres::search_entry_rows($dbh, $sqlq);
			my $id = $tmp[0][0];

			if (defined ($id))
			{
				# delete ft of uid
				$sqlq = "delete from ft where id = $id";
				Yaffas::Postgres::del_entry($dbh, $sqlq);

				# delete msn(s) of uid
				if (Yaffas::Check::faxtype() eq "AVM")
				{
					$sqlq = "delete from msn_avm where id = $id";
				}
				else
				{
					$sqlq = "delete from msn_eicon where id = $id";
				}
				Yaffas::Postgres::del_entry($dbh, $sqlq);

				# delete uid
				$sqlq = "delete from ug where id = $id";
				Yaffas::Postgres::del_entry($dbh, $sqlq);
			}
			Yaffas::Postgres::pg_disconnect($dbh);
		}
		if(-e Yaffas::Constant::DIR->{jpeg_dir}.$login.".jpg") {
			unlink(Yaffas::Constant::DIR->{jpeg_dir}.$login.".jpg");
		}

		if(-e Yaffas::Constant::DIR->{eps_dir}.$login.".eps") {
			unlink(Yaffas::Constant::DIR->{eps_dir}.$login.".eps");
		}

		unless ($? == 0)
		{
			Yaffas::Exception->throw("err_del_userjpeg" , $! );
		}

		# move users pdf dir to print operator readable dir
		my $pdf_user_dir = Yaffas::Constant::DIR->{'pdf_user_dir'}.$login;
		if( -d $pdf_user_dir) {
			my $new_dir = Yaffas::Constant::DIR->{'pdf_user_dir'};
			opendir(DIR, $new_dir) or throw Yaffas::Exception('err_opendir', $new_dir);
			my $count = '000';
			my @files = sort(readdir DIR);
			closedir DIR;
			foreach my $file (@files) {
				if($file =~ /^$login\.deleted\.(\d\d\d)$/) {
					$count = $1;
				}
			}
			$count++;
			$new_dir .= "$login.deleted.$count";
			rename $pdf_user_dir, $new_dir or throw Yaffas::Exception('err_rename_dir', $pdf_user_dir);
		}
	}
	catch Yaffas::Exception with {
		shift()->throw();
	};
}

=item password ( USERNAME, PASSWORD )

Sets the password of user with USERNAME to PASSWORD.
Returns 1 on success else C<undef>.

=cut

sub password($$) {
	my $login = shift;
	my $pass = shift;
	my $success = 1;

	my $cmd;
	$pass =~ s/\$/\\\$/g;
	$pass =~ s/"/\\"/g;

	if(user_exists_local($login)){
		$cmd = "/usr/bin/expect";

		open(PASS, "|$cmd") or ($success = undef);
		
		print PASS "spawn ".Yaffas::Constant::APPLICATION->{passwd}." $login";
		print PASS "\n";
		print PASS 'expect "*password:"';
		print PASS "\n";
		print PASS 'sleep 1';
		print PASS "\n";
		print PASS 'send "' . $pass . '\r"';
		print PASS "\n";
		print PASS 'expect "*password:"';
		print PASS "\n";
		print PASS 'sleep 1';
		print PASS "\n";
		print PASS 'send "' . $pass . '\r"';
		print PASS "\n";
		print PASS 'expect eof';
		print PASS "\n";
	
		close(PASS) or ($success = undef);
		throw Yaffas::Exception("err_change_password $cmd", $login) unless $success;
		
	}elsif(user_exists($login)){
		Yaffas::Exception->throw('err_no_local_auth')
		unless ( Yaffas::Auth::auth_type eq Yaffas::Auth::Type::LOCAL_LDAP
				 || Yaffas::Auth::auth_type eq Yaffas::Auth::Type::FILES );

		$cmd = Yaffas::Constant::APPLICATION->{smbldap_passwd}." '$login'";
		open(PASS, "|$cmd > /dev/null 2>&1") or ($success = undef);
		print PASS $pass, "\n";
		print PASS $pass, "\n";
		
		close(PASS) or ($success = undef);

		throw Yaffas::Exception("err_change_password $cmd", $login) unless $success;

	}
	throw Yaffas::Exception("err_change_passwd", $login) unless $cmd;


	1;
}

=item gecos ( USER, [ GIVENNAME, SURNAME ] )

It returns the Gecos of the USER.
If NEWGECOS is specified it sets a new gecos and returns it.
If a error occures it returns undef.

=cut

sub gecos($;$$) {
	my $user = shift;
	my $givenname = shift;
	my $surname = shift;

	if (defined $givenname and defined $surname) {
		Yaffas::Exception->throw('err_no_local_auth')
		unless ( Yaffas::Auth::auth_type eq Yaffas::Auth::Type::LOCAL_LDAP
				 || Yaffas::Auth::auth_type eq Yaffas::Auth::Type::FILES );

		my $gecos = _fix_gecos("$givenname $surname");
		unless (Yaffas::Check::gecos($gecos)) {
			throw Yaffas::Exception('err_gecos', $user);
		}
		do_back_quote(Yaffas::Constant::APPLICATION->{usermod}, "-c", $gecos, $user);
		my $ret = Yaffas::LDAP::replace_entry($user, "cn", "$givenname $surname");
		$ret += Yaffas::LDAP::replace_entry($user, "displayName", "$givenname $surname");
		Yaffas::LDAP::del_entry($user, "description");
		throw Yaffas::Exception("err_gecos", $user) unless ($? == 0 and $ret == 0);
		return $gecos;
	} else {
		return ((getpwnam($user))[6]);
	}
}

=item user_exists_local

=cut

sub user_exists_local($){
	my $user = shift;
	my $file = Yaffas::File::Config->new( Yaffas::Constant::FILE()->{passwd},
									 {
									  -SplitPolicy => 'custom',
									  -SplitDelimiter => ':',
									 }
								   );
	my $cfg = $file->get_cfg_values();
	return exists $cfg->{$user};
}


=item get_local_users

returns a list of all users of /etc/passwd

=cut

sub get_local_users(){
	my $file = Yaffas::File::Config->new( Yaffas::Constant::FILE()->{passwd},
									 {
									  -SplitPolicy => 'custom',
									  -SplitDelimiter => ':',
									 }
								   );
	return keys %{$file->get_cfg_values()};
}
=item get_user_entries ( [GROUP] )

get_user_entries creates a list of users on the system and returns it.
if GROUP is omitted it returns all users with a uid beteween 501 and 65000.
Machineaccounts (usernames ending with a $) are also skipped.
if you specify GROUP it returns the users of the GROUP. GROUP can be a GID
or the Groupname.

=cut

sub get_user_entries(;$) {
	my $group = shift;
	my (@theusers , @tmp, $i, @line, $uid, $username, $gid);

	if( (!defined( $group )) or $group eq ""){
		## list of all users
		foreach my $user (@{ getent("passwd") })
		{
			($username, undef,$uid, $gid) = split(/:/, $user);

			my $min_uid = 501;
			$min_uid = 500 if Yaffas::Constant::OS eq 'RHEL5';

			if ( $uid >= $min_uid && $username =~ /^.*[^\$]$/ && $username ne "nobody" && $username ne "nfsnobody") {
				push (@theusers, $username);
			}
		}
		return @theusers;
	}
	elsif ( $group =~ /^\d*$/ ){
		## GID
		my @tmp = split " ", (getgrgid($group))[3];
		return @tmp if (@tmp);
		return undef;
	}
	else {
		## Group name
		# use 'getent group' cos otherwise values will be cached
		foreach my $grp (@{ getent("group") }) {
			my ($tmpgrp, $tmpusers) = $grp =~ m/^([^:]*):[^:]*:[^:]*:(.*)$/;
			next unless $tmpgrp eq $group;
			my @users = split ",", $tmpusers;
			return @users if (@users);
			return undef;
		}
	#	# I know this looks silly, but it works ;-)
	#	# without adding "1" at the end of the array perl will cache it
	#	# and return old values
	#	my @tmp = ((split " ", (getgrnam($group))[3]), 1);
	#	splice(@tmp, -1, 1);
	#	return @tmp if (@tmp);
	#	return undef;
	}
	return( undef );
}

=item get_users ( [GROUP] )

Same as get_user_entries, except that zarafa resources are filtered out.

=cut

sub get_users(;$) {
	my $group = shift;

	my @users = get_user_entries($group);
	if ( Yaffas::Product::check_product("zarafa") ) {
		@users = grep {
			my @tmp =
			  Yaffas::do_back_quote(
				Yaffas::Constant::APPLICATION->{'zarafa_admin'},
				'--details', $_ );
			my $is_resource = 0;
			foreach (@tmp) {
				next unless $_ =~ m/^Auto-accept meeting req:\s*(yes|no)/;
				$is_resource = 1 if $1 eq 'yes';
			}
			$is_resource == 0;
		} @users;
	}
	return @users;
}

=item get_users_full

Same es get_users(), but creates a hashref of hashrefs of users. Keys are
usernames, values are 'uid', 'gid' and 'gecos' which are the keys for the
second level of the hashref.

=cut

sub get_users_full {
	my $group        = shift;
	my $user_entries = get_user_entries_full($group);

	if ( Yaffas::Product::check_product("zarafa") ) {
		foreach my $user ( keys %$user_entries ) {
			my @tmp =
			  Yaffas::do_back_quote(
				Yaffas::Constant::APPLICATION->{'zarafa_admin'},
				'--details', $user );
			my $is_resource = 0;
			foreach (@tmp) {
				next unless $_ =~ m/^Auto-accept meeting req:\s*(yes|no)/;
				$is_resource = 1 if $1 eq 'yes';
			}
			if ($is_resource) {
				delete $user_entries->{$user};
			}
		}
	}

	return $user_entries;
}

=item get_user_entries_full

Same es get_user_entries(), but creates a hashref of hashrefs of users. Keys
are usernames, values are 'uid', 'gid' and 'gecos' which are the keys for the
second level of the hashref.

=cut

sub get_user_entries_full {
	my $group = shift;
	my (@tmp, $uid, $username, $gid, $gecos);
	my $theusers = {};

	## list of all users
	foreach my $user (@{ getent("passwd") })
	{
		($username, undef,$uid, $gid, $gecos) = split(/:/, $user);

		my $min_uid = 501;
		$min_uid = 500 if Yaffas::Constant::OS eq 'RHEL5';

		if ( $uid >= $min_uid && $username =~ /^.*[^\$]$/ && $username ne "nobody" && $username ne "nfsnobody") {
			$theusers->{$username} = { uid => $uid, gid => $gid, gecos => $gecos };
		}
	}

	if( (!defined( $group )) or $group eq ""){
		return $theusers;
	}
	elsif ( $group =~ /^\d*$/ ){
		## GID
		my @tmp = split " ", (getgrgid($group))[3];
		my $grpusers;
		foreach my $user (@tmp) {
			$grpusers->{$user} = $theusers->{$user};
		}
		return $grpusers;
	}
	else {
		foreach my $grp (@{ getent("group") }) {
			my ($tmpgrp, $tmpusers) = $grp =~ m/^([^:]*):[^:]*:[^:]*:(.*)$/;
			next unless $tmpgrp eq $group;
			my $grpusers;
			foreach my $user (split ",", $tmpusers) {
				 $grpusers->{$user} = $theusers->{$user};
			}
			return $grpusers;
		}
	}
	return( undef );
}

=item get_users_utf8( [GROUP] )

Same as get_users() but with UTF-8 encoding and not ISO8859-1.

=cut

sub get_users_utf8(;$) {
	my $group = shift;
	my $c = Text::Iconv->new("utf-8", "iso8859-1");
	my @users = get_users($group);
	@users = map($c->convert($_), @users);
	return @users;
}


=item get_system_users ()

returns a list of all system users, excluding users with gid 501

=cut

sub get_system_users()
{
	return grep{$_} map{ (/^(.*):.*:\d+:(\d+):.*$/ && $2 != 500) ? $1 : undef  } @{ getent("passwd") };
}

=item get_groups ()

returns a List of all existings GID between 501 and 65000 plus admin groups (e.g. Domain Admins)

=cut

sub get_groups () {
	return grep {$_} map {(/^(.*):.*:(.*):.*$/ &&
			       ($2 >= 501 &&  $2 < 65000) ||
			       (grep {$1 eq $_} @{Yaffas::Constant::MISC->{admin_groups}}))
			       ? $1 : undef} @{ getent("group") };
}

=item get_all_groups_name ()

returns a list of ALL group names.

=cut

sub get_all_groups_name () {
	return grep {$_} map {(/^(.*):.*:.*:.*$/) ? $1 : undef} @{getent("group")};
}

=item get_groups_name ()

works like get_groups() but returns the Groupnames instead of the GID

=cut

sub get_groups_name() {
	return grep {$_} map {(/^(.*):.*:(.*):.*$/ && $2 >= 501 &&  $2 < 65000) ? $1 : undef} @{getent("group")};
}

=item get_groupname_by_gid ( GID )

Returns the groupname of the GID. undef on error.

=cut

sub get_groupname_by_gid($) {
    my $id = shift;
    for (@{getent("group")}) {
        return $1 if (/^(.*):.*:$id:.*$/)
    }
    return undef;
}

=item get_gid_by_groupname ( GROUPNAME )

It returns the GID of the GROUPNAME. undef on error.

=cut

sub get_gid_by_groupname($) {
    my $group = shift;
    for (@{getent("group")}) {
        return $1 if /^$group:.:([^:]+):/
    }
    return undef;
}

=item get_suppl_groupids( USERNAME )

Gets supplementary group out of 'getent groups'
and returns the groupid

=cut

sub get_suppl_groupids($) {
    my $user = shift;
    my @supplgroup;
    my @tmp = @{ getent("group") };

    foreach (@tmp) {
        if ( m/^([^:]+):[^:]+:([^:]+):(.*)$/ ){
            next if $1 eq "bkusers";
            next unless grep {$user eq $_} split ",", $3;
            push @supplgroup, $2;
        }
    }
    return @supplgroup;
}

=item get_suppl_groupnames ( USERNAME )

Gets supplementary group out of 'getent groups'
and returns the groupnames

=cut

sub get_suppl_groupnames($) {
    my $user = shift;
    my @supplgroup;
    my @tmp = @{ getent("group") };

    foreach (@tmp) {
        if ( m/^([^:]+):[^:]+:([^:]+):(.*)$/ ){
            next if $1 eq "bkusers";
            next unless grep {$user eq $_} split ",", $3;
            push @supplgroup, $1;
        }
    }
    return @supplgroup;
}

=item set_suppl_groups (USER, GROUPS)

Sets joins the USER to the given GROUPS. GROUPS can be names or GIDs.
throws a Yaffas::Exception on error.

=cut

sub set_suppl_groups ($@){
	my $user = shift;
	my @groups = @_;
	if ($user =~ /^\d+$/) {
		$user = get_username_by_uid($user);
	}

	unless (Yaffas::Check::username($user)) {
		throw Yaffas::Exception('err_username');
	}

	unless (user_exists($user)) {
		warn "User does not exists!";
		return;
	}

	for (@groups) {
		if (/^\d+$/) {
			$_ = get_groupname_by_gid($_);
		}
		# removed check so we can add users to "Print Operators" group
		#unless (Yaffas::Check::groupname($_)) {
		#	throw Yaffas::Exception('err_groupname', $_);
		#}
	}

	my $gid = join ",", @groups;
	my @cmd = ();
	push @cmd, Yaffas::Constant::APPLICATION->{usermod};
	push @cmd, "-G", $gid;
	push @cmd, $user;

	Yaffas::do_back_quote(@cmd);
    unless ($? == 0) {
		throw Yaffas::Exception("err_set_suppl_group", $? >> 8);
	}
	1;
}

=item is_user_in_group ( USER, GROUP )

It checks if a USER is in the GROUP.
returns the number of how often the USER is in the GROUP.
Usually 0 or 1 ;)
Returns undef on error.

=cut

sub is_user_in_group ($$) {
    my $user = shift;
    my $group = shift;
    return undef unless ($user and $group);
	my @users = get_users($group);
    return scalar grep {$_ eq $user if (defined($_))} get_users($group);
}

=item user_exists ( USERNAME )

Check if user with USERNAME exists. Return 1 if true else undef.

=cut

sub user_exists ($) {
	my $user = shift;
	my @users = get_user_entries();

	return 1 if (grep (/^$user$/, @users));
	return undef;
}

=item group_exists ( GROUPNAME )

Check if a GROUPNAME exists. Return 1 if true else undef;

=cut

sub group_exists ($) {
	my $group = shift;
	my @groups = grep {$_} map {/^(.*):.*:.*:.*$/ ? $1 : undef} @{ getent("group") };
	return 1 if (grep {$group eq $_} @groups);
	return undef;
}

=item get_uid_by_username ( USERNAME )

Returns uid by given USERNAME or undef if USERNAME not found.

=cut

sub get_uid_by_username ($) {
	my $user = shift;
	return undef unless($user);
	return undef unless getent("passwd_data_name")->{$user};
	my $line =  getent("passwd_data_name")->{$user};
	return( (split(/:/, $line))[2] );
}

=item get_username_by_uid ( UID )

Returns the username of the UID, and undef if the UID is not found.

=cut

sub get_username_by_uid ($) {
	my $uid = shift;
	#we use a random number to prevent perl from caching
	my ($login) = (getpwuid($uid),rand) or return undef;
	return $login;
}

=cut

=item get_email (USER)

This routine returns the given users email. If there is no mail address
the return code will be a bloody undef.

=cut

sub get_email($)
{
	my $user = shift;
	my ($mail) = Yaffas::LDAP::search_attribute('user',"$user", 'mail');

	return undef unless $mail;
	return $mail;
}

=item set_email ( USER EMAILADRESS )

This sub sets the email adress in the LDAP for this USER.
throws Yaffas::Exception on error.

=cut

sub set_email($$) {
	my $user = shift;
	my $email = shift;

	Yaffas::Exception->throw('err_no_local_auth')
	  unless ( Yaffas::Auth::auth_type eq Yaffas::Auth::Type::LOCAL_LDAP
		|| Yaffas::Auth::auth_type eq Yaffas::Auth::Type::FILES );

	unless (Yaffas::Check::email($email)) {
		throw Yaffas::Exception("err_email");
	}

	my $r;	my $got_it = Yaffas::LDAP::search_entry("uid=$user", 'mail');

	if ($got_it) {
		$r = Yaffas::LDAP::replace_entry($user, "mail", $email);
		throw Yaffas::Exception("err_email", $r) if $r;
	} else {
		$r = Yaffas::LDAP::add_entry($user, "mail", $email);
		throw Yaffas::Exception("err_email", $r) if $r;
	}


}
=item del_email( USER )

This routine deletes the user's email.
throws Yaffas::Exception on error.


=cut


sub del_email($) {
	my $r;

	Yaffas::Exception->throw('err_no_local_auth')
	  unless ( Yaffas::Auth::auth_type eq Yaffas::Auth::Type::LOCAL_LDAP
		|| Yaffas::Auth::auth_type eq Yaffas::Auth::Type::FILES );

	my $got_it = Yaffas::LDAP::search_entry("sn=$_[0]", 'email');
	if($got_it){
		$r = 	Yaffas::LDAP::del_entry($_[0], "email");
		throw Yaffas::Exception("err_email", $r) if $r;
	}
}
=item get_crypted_passwd( USER )

This routine returns the crypted password for B<USER>.

=cut

sub get_crypted_passwd($){
    my $user = shift;
    my @pw = do_back_quote(Yaffas::Constant::APPLICATION->{usershow}, $user);
	foreach my $pw (@pw)
	{
	 	chomp $pw;
		return $1 if $pw =~ m/userPassword: {CRYPT}(.+)$/;
	}
}

=item mod_user_ftype( HASHREF  )

Modifies users Hylafach attachemant filetype address.
 HASHREF is user->ftype.
 Throws exception on error.

=cut

sub mod_user_ftype(%) {
	my $user_ftype = shift;
	
	my $ret = undef;
	my $throw_exc = 0;
	my $exception = Yaffas::Exception->new();
	
	while (my ($user, $ftype) = each%{$user_ftype})
	{
		if (! Yaffas::UGM::user_exists($user) )
		{
			$exception->add("err_user_doesnt_exist", $user);
			$throw_exc = 1;
		}
		if ( $ftype ne 'pdf' && $ftype ne 'ps' && $ftype ne 'tif'  && $ftype ne 'gif' && $ftype ne 'jpg' )
		{
			$exception->add("err_bad_ft", $ftype);
			$throw_exc = 1;
		}
		throw $exception if ($throw_exc == 1);

		my $dbh;
		if (Yaffas::Product::check_product('fax'))
		{
			$dbh = Yaffas::Postgres::connect_db("bbfaxconf");
		}
		if (defined($dbh))
		{
			# does user exists?
			my $sqlq = "select id from ug where ug='$user' and type='u'";
			unless ( scalar (Yaffas::Postgres::search_entry_rows($dbh, $sqlq)) )
			{
				$sqlq = "insert into ug (ug, type) values ('$user', 'u')";
				$ret = Yaffas::Postgres::add_entry($dbh, $sqlq);
			}
			
			# exists an entry? update it
			$sqlq = "select ft.filetype from ug,ft where ug.id = ft.id and ug.ug = '$user' and ug.type = 'u'";
			if ( scalar (Yaffas::Postgres::search_entry_rows($dbh, $sqlq)) )
			{
				$sqlq = "update ft set filetype = '$ftype' from ug where ug.id = ft.id and ug.ug = '$user' and ug.type = 'u'";
				$ret =  Yaffas::Postgres::replace_entry($dbh, $sqlq);
			}
			else
			{
				# no entry? insert it.
				# get id of entry.
				$sqlq = "select id from ug where ug = '$user' and type = 'u'";
				my @tmp = Yaffas::Postgres::search_entry_rows($dbh, $sqlq);
				my $id = $tmp[0][0];

				if (defined($id))
				{
					$sqlq = "insert into ft (id, filetype) values ($id, '$ftype')";
					$ret =  Yaffas::Postgres::add_entry($dbh, $sqlq);
				}
			}
			Yaffas::Postgres::pg_disconnect($dbh);
		}
	}

	return $ret;
}

=item mod_group_ftype( HASHREF  )

Modifies groups Hylafach attachemant filetype address.
 HASHREF is group->ftype.
 Throws exception on error.

=cut

sub mod_group_ftype(%) {
	my $group_ftype = shift;

	my $ret = undef;
	my $throw_exc = 0;
	my $exception = Yaffas::Exception->new();
	
	while (my ($group, $ftype) = each%{$group_ftype}) {
		if (! Yaffas::UGM::group_exists($group) ) {
			$exception->add("err_group_dosent_ex", $group);
			$throw_exc = 1;
		}

		if ( $ftype ne 'pdf' && $ftype ne 'ps' && $ftype ne 'tif'  && $ftype ne 'gif') {
			$exception->add("err_bad_ft", $ftype);
			$throw_exc = 1;
		}
		throw $exception if ($throw_exc == 1);

		my $dbh;
		if (Yaffas::Product::check_product('fax'))
		{
			$dbh = Yaffas::Postgres::connect_db("bbfaxconf");
		}

		if (defined($dbh))
		{
			# does user exists?
			my $sqlq = "select id from ug where ug='$group' and type='g'";
			unless ( scalar (Yaffas::Postgres::search_entry_rows($dbh, $sqlq)) )
			{
				$sqlq = "insert into ug (ug, type) values ('$group', 'g')";
				$ret = Yaffas::Postgres::add_entry($dbh, $sqlq);
			}

			# exists an entry? update it
			$sqlq = "select ft.filetype from ug,ft where ug.id = ft.id and ug.ug = '$group' and ug.type = 'g'";
			if ( scalar (Yaffas::Postgres::search_entry_rows($dbh, $sqlq)) )
			{
				$sqlq = "update ft set filetype = '$ftype' from ug where ug.id = ft.id and ug.ug = '$group' and ug.type = 'g'";
				$ret =  Yaffas::Postgres::replace_entry($dbh, $sqlq);
			}
			else
			{
				# no entry? insert it.
				# get id of entry.
				$sqlq = "select id from ug where ug = '$group' and type = 'g'";
				my @tmp = Yaffas::Postgres::search_entry_rows($dbh, $sqlq);
				my $id = $tmp[0][0];

				if (defined($id))
				{
					$sqlq = "insert into ft (id, filetype) values ($id, '$ftype')";
					$ret =  Yaffas::Postgres::add_entry($dbh, $sqlq);
				}
			}
			Yaffas::Postgres::pg_disconnect($dbh);
		}
	}

	return $ret;
}

=item rename_login ( OLD, NEW )

Changes the the OLD loginname of a user to NEW.
Throws an exception on error.

=cut

sub rename_login ($$) {
	my $old = shift;
	my $new = shift;

	throw Yaffas::Exception("err_user_exists", $old) unless (user_exists($old));
	#throw Yaffas::Exception("err_user_already_exists", $new) if (user_exists($new));

	# is there an alias already with the same name?
	my $alias = Yaffas::Mail::Mailalias->new();
	if ($alias->get_alias_destination($new)) {
		throw Yaffas::Exception('err_name_is_alias', $new);
	}

	my $ret = Yaffas::do_back_quote(Yaffas::Constant::APPLICATION->{usermod}, "-r", $new, $old);

	throw Yaffas::Exception("err_rename_login", $ret) unless($? == 0);
}

=item get_hylafax_filetype ( USER/GROUP TYPE )

Returns filetype of user or group.
Undef on Error

USER/GROUP name
TYPE 'u' for user, 'g' for group

=cut

sub get_hylafax_filetype ($$)
{
	my $ug = shift;
	my $type = shift;

	my $dbh;
	if (Yaffas::Product::check_product('fax'))
	{
		$dbh = Yaffas::Postgres::connect_db("bbfaxconf");
	}
	my @ftype = ();

	if (defined($dbh))
	{
		my $sqlq = "select ft.filetype from ft,ug where ug.ug='$ug' and ug.type = '$type' and ug.id = ft.id";
		@ftype = Yaffas::Postgres::search_entry_rows($dbh, $sqlq);
		Yaffas::Postgres::pg_disconnect($dbh);
	}

	defined($ftype[0][0]) ? return $ftype[0][0] : return undef;
}

sub _get_winbind_separator() {
	my $smb = File::Samba->new( Yaffas::Constant::FILE->{'smb_includes_global'} )
	or throw Yaffas::Exception("err_file_read", Yaffas::Constant::FILE->{smb_includes_global});
	my $sep = $smb->value("global", "winbind separator");
	return $sep;
}

=item get_print_operators_group ()

Returns the print operators group.

=cut

sub get_print_operators_group() {
	my $winbind_sep = _get_winbind_separator();
	my $smb = File::Samba->new(Yaffas::Constant::FILE->{samba_conf});
	my $prnopgrp = $smb->value('print$', 'force group');
	if (defined $prnopgrp) {
		$prnopgrp =~ s/"//g;
		if(defined $winbind_sep) {
			$prnopgrp =~ s/.+$winbind_sep//;
		}
		return $prnopgrp;
	}
	return undef;
}

=item set_print_operators_group ( GROUP, [ADMIN, ADMIN PWD] )

Sets the print operators group to B<GROUP>.

If B<ADMIN> and B<ADMIN PWD> are supplied the B<SePrintOperatorPrivilege> will
be granted to the given B<GROUP> for the current domain.

B<GROUP> is expected to be UTF-8 encoded.

=cut

sub set_print_operators_group($;$$) {
	my $group = shift;
	my $admin = shift;
	my $adminpw = shift;

	# for cgi output we have to use iso encoding
	# for internal use and system calls we habe to use utf8 encoding

	clear_cache();

	my $old_group = get_print_operators_group();

	if(! grep { $_ eq "$group" } get_all_groups_name()) {
		my $chars = join '.*', split / */, $group;
		my @altgroup = grep {$_} map { /^(.*$chars.*)$/i ? $1 : undef } get_all_groups_name();
		my @msg = ("$group");
		$altgroup[0] and push @msg, "did you mean: ".(join " or ", map { $_ = "'$_'"; } @altgroup).'?';
		throw Yaffas::Exception("err_printop_group", \@msg);
	}
	my $dom_group = $group;
	if(Yaffas::Auth::get_auth_type() eq ADS or Yaffas::Auth::get_auth_type() eq PDC) {
		my $workgroup = uc _get_workgroup();
		my $winbind_sep = _get_winbind_separator();

		$dom_group = $workgroup.$winbind_sep.$group;
	}

	my $error = 0;
	my $smb_conf = Yaffas::File->new(Yaffas::Constant::FILE->{samba_conf})
		or throw Yaffas::Exception("err_file_read", Yaffas::Constant::FILE->{samba_conf});
	my $linenr = $smb_conf->search_line(qr/force group/i);
	if(defined $linenr) {
		$smb_conf->splice_line($linenr, 1, " " x 8 . 'force group = "'.$dom_group.'"');
	}
	else {
		$error++;
	}
	$linenr = $smb_conf->search_line(qr/valid users/i);
	if(defined $linenr) {
		$smb_conf->splice_line($linenr, 1, " " x 8 .'valid users = @"'.$dom_group.'"');
	}
	else {
		$error++;
	}
	$linenr = $smb_conf->search_line(qr/write list/i);
	if(defined $linenr) {
		$smb_conf->splice_line($linenr, 1, " " x 8 . 'write list = @"'.$dom_group.'"');
	}
	else {
		$error++;
	}
	# set print operators in smbopts.fax
	my $smbconf_fax = Yaffas::File->new(Yaffas::Constant::FILE->{smbconf_fax})
		or throw Yaffas::Exception("err_file_read", Yaffas::Constant::FILE->{smbconf_fax});
	my @content = $smbconf_fax->get_content();
	for (my $ln = 0; $ln < scalar @content; $ln++) {
		if($content[$ln] =~ m/valid users/i) {
			$smbconf_fax->splice_line($ln, 1, " " x 8 . 'valid users = @"'.$dom_group.'"');
		}
		elsif($content[$ln] =~ m/read list/i) {
			$smbconf_fax->splice_line($ln, 1, " " x 8 . 'read list = @"'.$dom_group.'"');
		}
	}
	$smbconf_fax->write();

	if($error) {
		throw Yaffas::Exception("err_print_share");
	}
	else {
		$smb_conf->write();
		if (Yaffas::Product::check_product("fax")) {
			# Copy smb.conf to hylafax etc. Needed by hfaxd
			my $hylafax_etc = Yaffas::Constant::DIR->{hylafax};
			copy(Yaffas::Constant::FILE->{samba_conf}, $hylafax_etc);
			Yaffas::Service::control(HYLAFAX, RESTART);
		}
		# fix smbconf.allpdfs
		my $smbconf_allpdfs = Yaffas::File->new(Yaffas::Constant::FILE->{smb_allpdfs})
			or throw Yaffas::Exception("err_file_read", Yaffas::Constant::FILE->{smb_allpdfs});
		$linenr = $smbconf_allpdfs->search_line(qr/valid users/i);
		if(defined $linenr) {
			$smbconf_allpdfs->splice_line($linenr, 1, " " x 8 . "valid users = \@\"$dom_group\"");
		}
		$smbconf_allpdfs->write();

		my $ret = Yaffas::do_back_quote_2("/bin/chgrp", "-R", "$group", "/etc/samba/printer");
		$ret and throw Yaffas::Exception("err_chgrp_printer", [$ret, "group: $group"]);
		$ret = Yaffas::do_back_quote_2("/bin/chmod", "-R", "0775", "/etc/samba/printer");
		$ret and throw Yaffas::Exception("err_chmod_printer", $ret);
		unless( -d Yaffas::Constant::DIR->{pdf_user_dir}) {
			mkpath(Yaffas::Constant::DIR->{pdf_user_dir}, 0, 0775);
		}
		$ret = Yaffas::do_back_quote_2("/bin/chgrp", "-R", "$group", Yaffas::Constant::DIR->{pdf_user_dir});
		$ret and throw Yaffas::Exception("err_chgrp", [$ret, Yaffas::Constant::DIR->{pdf_user_dir}]);

		if(defined $admin and defined $adminpw) {
			# set SePrintOperatorPrivilege for group
			my $dom = _get_workgroup();
			defined $dom or throw Yaffas::Exception("err_no_workgroup");
			# this only works with the one argument version of system!
			$ret = Yaffas::do_back_quote_2("/usr/bin/net rpc rights revoke \"$dom\\$old_group\" SePrintOperatorPrivilege -U$admin\%$adminpw > /dev/null");
			if($ret && grep { $_ eq "$old_group" } get_all_groups_name()) {
				throw Yaffas::Exception("err_revoke_privilege", [$ret, "domain: $dom", "group: ".$old_group, "admin: $admin"]);
			}
			$ret = Yaffas::do_back_quote_2("/usr/bin/net rpc rights grant \"$dom\\$group\" SePrintOperatorPrivilege -U$admin\%$adminpw > /dev/null");
			$ret and throw Yaffas::Exception("err_grant_privilege", [$ret, "domain: $dom", "group: $group", "admin: $admin"]);
		}
	}
}

sub _get_workgroup() {
	my $conf = Yaffas::File::Config->new(Yaffas::Constant::FILE->{'smb_includes_global'},
			{
				-SplitPolicy => 'custom',
				-SplitDelimiter => '\s*=\s*',
				-StoreDelimiter => '=',
			}
		);
	my $values = $conf->get_cfg_values();
	return $values->{workgroup};
}

=item name ( LOGIN, [ GIVENNAME, SURNAME ] )

Sets the name of the given LOGIN user. Also sets the gecos.

=cut

sub name($;$$) {
	my $login = shift;
	my $givenname = shift;
	my $surname = shift;

	if (defined $givenname and defined $surname) {
		gecos($login, $givenname, $surname);

		my $ret = 0;
		$ret += Yaffas::LDAP::replace_entry($login, "givenName", $givenname);
		$ret += Yaffas::LDAP::replace_entry($login, "sn", $surname);

		if ($ret != 0) {
			throw Yaffas::Exception("err_change_name");
		}
	}
	else {
		$givenname = (Yaffas::LDAP::search_attribute("user", $login, "givenName"))[0];
		$surname = (Yaffas::LDAP::search_attribute("user", $login, "sn"))[0];

		$givenname = "" unless defined $givenname;
		$surname = "" unless defined $surname;
	}

	return ($givenname, $surname);
}

sub _fix_gecos($) {
	my $gecos = shift;

	$gecos =~ s/ö/oe/g;
	$gecos =~ s/ä/ae/g;
	$gecos =~ s/ü/ue/g;
	$gecos =~ s/Ö/Oe/g;
	$gecos =~ s/Ä/Ae/g;
	$gecos =~ s/Ü/Ue/g;
	$gecos =~ s/ß/ss/g;

	return $gecos;
}

sub set_additional_values {
    my $login = shift;
    my $values = shift;

    throw Yaffas::Exception("err_values") unless ref $values eq "HASH";

    foreach my $k (keys %{$values}) {
        Yaffas::LDAP::replace_entry($login, $k, $values->{$k});
    }
}

sub get_additional_value {
    my $login = shift;
    my $key = shift;

    return (Yaffas::LDAP::search_attribute("user", $login, $key))[0];
}

sub get_send_as {
    my $login = shift;

    my @uids = Yaffas::LDAP::search_attribute("user", $login, "zarafaSendAsPrivilege");
    my @ret;

    foreach my $uid (@uids) {
        push @ret, get_username_by_uid($uid);
    }
    return @ret;
}

sub set_send_as {
    my $login = shift;
    my $values = shift;

    throw Yaffas::Exception("err_values") unless ref $values eq "ARRAY";

    my @idvals;

    for my $v (@{$values}) {
        my $uid = get_uid_by_username($v);
        push @idvals, $uid if ($uid >= 0);
    }

    if (Yaffas::Product::check_product("zarafa")) {
        Yaffas::LDAP::replace_entry($login, "zarafaSendAsPrivilege", \@idvals);
        system(Yaffas::Constant::APPLICATION->{zarafa_admin}, "--sync");
    }
}

1;

=back

=head1 COPYRIGHT

This file is part of yaffas.

yaffas is free software: you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

yaffas is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public
License for more details.

You should have received a copy of the GNU Affero General Public
License along with yaffas.  If not, see
<http://www.gnu.org/licenses/>.