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

package WorkLog::CGI;
use warnings;
use strict;

our $VERSION = sprintf "%d.%03d", q$Revision: 1.3 $ =~ /(\d+)/g;

use CGI;
#DEVONLY use CGI::Carp qw(fatalsToBrowser);
use WLCONFIG;
use vars qw(%c);
*c = \%WLCONFIG::conf;

my $cgi;

unless (defined $cgi) {
    $cgi = new CGI;
}

sub new {
    return $cgi;
}

1;
