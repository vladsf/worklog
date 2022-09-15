#!/usr/bin/perl

# This CGI script is part of the WorkLog software.
# Copyright (C) 2004 Andrew Sweger <yDNA@perlocity.org> & Addnorya
# Copyright (C) 2003 Matt Wagner <matt@mysql.com> & MySQL AB
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
#                     
# Originally derived from the work of Alex Shnitman <alexsh@hectic.net>
#

use warnings;
use strict;

BEGIN {
    push @INC, -f "/usr/local/etc/WLCONFIG.pm" ? "/usr/local/etc" : "./lib";
}

use WLCONFIG;
use vars qw(%c);
*c = \%WLCONFIG::conf;
use WorkLog::CGI;
use WorkLog qw(
    error
    get_catname
);
use WorkLog::Index qw(
    view_as_text
    view_search_results
    view_task
    view_virtual_task
    view_tasks
);

local $SIG{__DIE__} = sub {
    my $errmsg = shift;
    error $errmsg;
    exit 1;
};

my $cgi = new WorkLog::CGI;
my $url = $cgi->url( -absolute => 1 );
my $forms = "$c{misc}{baseurl}forms.pl";

########################################################################
######## Main dispatcher code

my $search = $cgi->param('search') || "";
if ( $cgi->param('astext') ) {
    view_as_text( $cgi->param('catname') );
}
elsif ( $cgi->param('tid') ) {
    my $cn = get_catname( $cgi->param('tid') );
    if ( $url !~ m/^$c{misc}{baseurl}${cn}\/.*$/ ) {
        print $cgi->redirect( "$c{misc}{baseurl}$cn/?tid=" . $cgi->param('tid') );
    }
    else {
        view_task( $cgi->param('tid') );
    }
}
elsif ( defined $cgi->param('virtual') ) {
    view_virtual_task( $cgi->param('virtual') );
}
elsif ( $search =~ m/^(WL\#)?([\d]+)$/i ) {
    my $cn = get_catname($2);
    if ( $url !~ m/^$c{misc}{baseurl}${cn}\/.*$/ ) {
        print $cgi->redirect("$c{misc}{baseurl}$cn/?tid=$2");
    }
    else {
        view_task($2);
    }
}
elsif ( $search =~ m/^(BUG\#)?([\d]+)$/i ) {
    print $cgi->redirect("$c{misc}{bugsdb}$2");
}
elsif ( $search ) {
    view_search_results( $search );
}
else {
    view_tasks( $cgi->param('catname') );
}

