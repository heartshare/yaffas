#!/usr/bin/perl
package Yaffas::Mail::Mailalias::File;

use strict;
use warnings;

use Yaffas::File::Config;

my %alias_file = (
				  "USER" => "/etc/aliases",
				  "DIR" => "/etc/aliases.dir"
				 );


sub _write {
	my $mode = shift;
	my %data = @_;

	my $bkc = Yaffas::File::Config->new($alias_file{$mode},
										{
										-SplitPolicy => 'custom',
										-SplitDelimiter => ':\s*',
										-StoreDelimiter => ': ',
										});
	$bkc->get_cfg()->save_file($alias_file{$mode}, \%data);
	return 1;
}

sub _read {
	my $mode = shift;
	my $bkc = Yaffas::File::Config->new($alias_file{$mode},
										{
										-SplitPolicy => 'custom',
										-SplitDelimiter => ':\s*',
										-StoreDelimiter => ': ',
										});
	return $bkc->get_cfg_values();
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