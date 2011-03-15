# file bbsupport-forms.pl 
# for all my bbfaxcardedit forms

use warnings;
use strict;

use Yaffas::UI;

sub get_infos {
	print $Cgi->start_form( {-action=>"save_support_infos.cgi",-method=>"post"} );
	print Yaffas::UI::section( $main::text{lbl_support},
							   $Cgi->p($main::text{lbl_klick_dl})
						 );
	print Yaffas::UI::section_button($Cgi->button({-id=>"dlsupport",-label=>$main::text{'lbl_download'}}));
	print $Cgi->end_form();
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
