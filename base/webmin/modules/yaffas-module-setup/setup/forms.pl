#!/usr/bin/perl -w

use strict;
use warnings;

use Yaffas::UI qw/textfield/;
use Yaffas::Exception;
use Yaffas::Product;
use Error qw(:try);

sub show_setup() {
    print $Cgi->start_form({-action=>"initialsetup.cgi", -method=>"post"});
    print Yaffas::UI::section("Setup", $Cgi->div( {-id=>"setup"},
            $Cgi->div({-id=>"page-1"},
                $Cgi->h2($main::text{lbl_basic_settings}." (1/4)"),
                $Cgi->table(
                    $Cgi->Tr(
                        $Cgi->td($main::text{lbl_admin_pw}.":"),
                        $Cgi->td($Cgi->password_field({-name=>"admin_password1"}))
                    ),
                    $Cgi->Tr(
                        $Cgi->td($main::text{lbl_admin_pw_repeat}.":"),
                        $Cgi->td($Cgi->password_field({-name=>"admin_password2"}))
                    ),
                ),
            ),
            Yaffas::Product::check_product("zarafa") ? (
                $Cgi->div({-id=>"page-2", -style=>"display: none"},
                    $Cgi->h2($main::text{lbl_zarafa_settings}." (2/4)"),
                    $Cgi->table(
                        $Cgi->Tr(
                            $Cgi->td($main::text{lbl_mysql_user}.":"),
                            $Cgi->td(textfield({-name=>"mysql_user"}))
                        ),
                        $Cgi->Tr(
                            $Cgi->td($main::text{lbl_mysql_password}.":"),
                            $Cgi->td(textfield({-name=>"mysql_password"}))
                        ),
                        $Cgi->Tr(
                            $Cgi->td($main::text{lbl_mysql_host}.":"),
                            $Cgi->td(textfield({-name=>"mysql_host"}))
                        ),
                        $Cgi->Tr(
                            $Cgi->td($main::text{lbl_mysql_database}.":"),
                            $Cgi->td(textfield({-name=>"mysql_database"}))
                        ),
                    )
                )
            ) : (),
            $Cgi->div({-id=>"page-3", -style=>"display: none"},
                $Cgi->h2($main::text{lbl_mailserver_settings}." (3/4)"),
                $Cgi->table(
                    map {
                    $Cgi->Tr(
                        $Cgi->td($main::text{"lbl_mailserver_".$_}.":"),
                        $Cgi->td(textfield({-name=>"mailserver_".$_}))
                    )
                    } qw(domain smarthost smarthost_user smarthost_password)
                )
            ),
            $Cgi->div({-id=>"page-4", -style=>"display: none"},
                $Cgi->h2($main::text{lbl_user_settings}." (4/4)"),
                $Cgi->table(
                    map {
                    $Cgi->Tr(
                        $Cgi->td($main::text{"lbl_user_".$_}.":"),
                        $Cgi->td($_ =~ /password/ ? $Cgi->password_field({-name=>"user_".$_}) : textfield({-name=>"user_".$_}))
                    )
                    } qw(login firstname surname email password password_repeat)
                )
            ),
            $Cgi->div({-id=>"page-3", -style=>"display: none"},
            ),
        )
    );
    print Yaffas::UI::section_button(
        $Cgi->button({-name=>"Prev", -id=>"prevPage"}),
        $Cgi->button({-name=>"Next", -id=>"nextPage"}),
        $Cgi->button({-id=>"submit", -value=>$main::text{'lbl_finish'}}),
    );
    print $Cgi->end_form();

    print $Cgi->div({id=>"logoutdlg"});
}


return 1;
=pod

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
