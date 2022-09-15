#
# WorkLog/Database.pm
#
# This library file is part of the WorkLog software.
# Copyright (C) 2004 Andrew Sweger <yDNA@perlocity.org> & Addnorya
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#   
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#   
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package WorkLog::Database;
use warnings;
use strict;

our $VERSION = sprintf "%d.%03d", q$Revision: 1.3 $ =~ /(\d+)/g;

use DBI;
use WLCONFIG;
use vars qw(%c);
*c = \%WLCONFIG::conf;

my $dbh;

unless (defined $dbh) {
    $dbh = DBI->connect(
        $c{db}{dsn},
        $c{db}{user},
        $c{db}{auth},
        {
            RaiseError => 1,
        }
      )
      or die "NO DB!\n";
}

sub new {
    return $dbh;
}

1;
