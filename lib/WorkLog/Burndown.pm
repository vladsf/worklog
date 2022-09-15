#
# WorkLog/Burndown.pm
#
# This library file is part of the WorkLog software.
# Copyright (C) 2004 Andrew Sweger <yDNA@perlocity.org> & Addnorya
# Copyright (C) 2003 Matt Wagner <mwagner@mysql.com> & MySQL AB
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

package WorkLog::Burndown;
use warnings;
no warnings 'uninitialized';
use strict;

our $VERSION = sprintf "%d.%03d", q$Revision: 1.9 $ =~ /(\d+)/g;

use Data::Dumper;
use POSIX qw(strftime);
use WorkLog::Database;
use WorkLog::CGI;
use WorkLog qw(
    all_children_of
    error
    page_start
    table_start
    get_devname
    get_status
    get_title
    mk_title
    page_end
);

local $SIG{__DIE__} = sub {
    my $errmsg = shift;
    error($errmsg);
    exit 1;
};

use WLCONFIG;
use vars qw(%c);
*c = \%WLCONFIG::conf;

######## Package File-Scope Variables (my globals)
    my $dbh        = '';   # Datbase handle
    my $cgi        = '';   # CGI handle
    my $inited     = 0;    # Have we already initialized


use subs qw(
);

######## Public Subroutines

sub print {
    my $tid = $cgi->param('tid');
    my $tasks = {};
    my @tids = ();
    my @children = ();
    my $statement = '';
    my $sth = '';
    my $title = '';

    my ($virtual_type, $virtual_selector) = $tid =~ /^(.*?):(.*)$/;
    if ($tid =~ /^\d+$/) {
        my $task_title = get_title $tid;
        $title = "$task_title ($tid)";
    }
    elsif ($virtual_type eq 'version') {
        $title = "Version: $virtual_selector";
        $statement = "SELECT id FROM tasks WHERE version = ?";
    }
    elsif ($virtual_type eq 'status') {
        my $status = get_status $virtual_selector;
        $title = "Status: $status";
        $statement = "SELECT id FROM tasks WHERE status = ?";
    }
    elsif ($virtual_type eq 'grpldr') {
        my $username = get_devname $virtual_selector;
        $title = "Supervisor: $username";
        $statement = "SELECT id FROM tasks WHERE supervisor = ?";
    }
    elsif ($virtual_type eq 'developer') {
        my $username = get_devname $virtual_selector;
        $title = "Developer: $username";
        $statement = "SELECT id FROM tasks WHERE developer = ?";
    }
    else {
        error("Invalid task ID or unknown virtual type in [$tid]");
    }

    if ($virtual_type) {
        $sth = $dbh->prepare($statement);
        $sth->execute($virtual_selector);
        while (my ($task) = $sth->fetchrow_array) {
            push @tids, $task;
            $tasks->{$task} = {};
        }
        for my $task (@tids) {
            my @tasks_children = all_children_of($task);
            for my $child (@tasks_children) {
                unless (exists $tasks->{$child}) {
                    push @children, $child;
                    $tasks->{$child} = {};
                }
            }
        }
    }

    my $subtasks = defined $cgi->param('subtasks') ? 1 : 0;
    my (%worked, %delta, @times, @dates);
    if ($virtual_type && $subtasks) {
        my $subtasklist = join ",", @tids, @children;
        $statement =
            "SELECT hrs_worked, estimate_delta, UNIX_TIMESTAMP(recorded), DATE_FORMAT(recorded, '%Y-%m-%d')"
          . "  FROM timelog"
          . " WHERE task_id IN ($subtasklist)"
          . " ORDER BY recorded"
          ;
    }
    elsif ($virtual_type) {
        my $subtasklist = join ",", @tids;
        $statement =
            "SELECT hrs_worked, estimate_delta, UNIX_TIMESTAMP(recorded), DATE_FORMAT(recorded, '%Y-%m-%d')"
          . "  FROM timelog"
          . " WHERE task_id IN ($subtasklist)"
          . " ORDER BY recorded"
          ;
    }
    elsif ($subtasks) {
        my $subtasklist = join ",", $tid, all_children_of($tid);
        $statement =
            "SELECT hrs_worked, estimate_delta, UNIX_TIMESTAMP(recorded), DATE_FORMAT(recorded, '%Y-%m-%d')"
          . "  FROM timelog"
          . " WHERE task_id IN ($subtasklist)"
          . " ORDER BY recorded"
          ;
    }
    else {
        $statement =
            "SELECT hrs_worked, estimate_delta, UNIX_TIMESTAMP(recorded), DATE_FORMAT(recorded, '%Y-%m-%d')"
          . "  FROM timelog"
          . " WHERE task_id = $tid"
          . " ORDER BY recorded"
          ;
    }
    $sth = $dbh->prepare($statement);
    $sth->execute;
    while (my @row = $sth->fetchrow_array) {
        my ($worked, $delta, $time, $date) = @row;
        $worked{$date} += $worked;
        $delta{$date}  += $delta;
        push @times, $time unless $times[-1] == $time;
        push @dates, $date unless $dates[-1] eq $date;
    }
    $sth->finish;
    print generate_html(\%worked, \%delta, \@dates, \@times, $title);
}

######## Private

sub generate_html {
    my ($worked, $delta, $dates, $times, $title) = @_;
    
    my $html_top =
          page_start("Burndown Report for $title")
        . table_start('minimal', { actions => 1, main => 1 } )
        . mk_title("Burndown Report for $title",1);
    my $table_start = "<table width=100% border=0>\n";
    my $table_end   = "</table>\n";
    my $html =
          $html_top
        . "<table width=70% border=0>\n"
        . "<tr><th align=right width=25%>Time Remaining:</th><td><img src=\"$c{misc}{baseurl}images/black.gif\" width=20 height=10></td></tr>\n"
        . "<tr><th align=right>Time Worked:</th><td><img src=\"$c{misc}{baseurl}images/silver.gif\" width=20 height=10></td></tr>\n"
        . "<tr><th align=right>Total Time:</th><td><img src=\"$c{misc}{baseurl}images/black.gif\" width=20 height=10><img src=\"$c{misc}{baseurl}images/silver.gif\" width=20 height=10></td></tr>\n"
        . "<tr><td>&nbsp;</td></tr>\n"
        . "</table>\n"
        . $table_start;

    my $start = $times->[0];
    my $end   = $times->[-1];
    my $SPD   = 24 * 3600;
    my $ttl_worked = 0;
    my $ttl_remain = 0;
    my $maxsum = 0;
    for (@$dates) {
        my $w = $worked->{$_};
        my $d = $delta->{$_};
        $ttl_worked += $w;
        $ttl_remain += $d;
        my $sum = $ttl_worked + $ttl_remain;
        $maxsum = $sum if $sum > $maxsum;
    }
    if ($maxsum > 0) {
        my $widthfactor = 500 / $maxsum;
        $ttl_worked = 0;
        $ttl_remain = 0;
        $html .= "<tr><th>Date</th><th>Hours Remain</th><th>&nbsp;</th></tr>\n";
        for (my $i = $start; $i < ($end + $SPD); $i += $SPD) {
            my $date = strftime "%Y-%m-%d", localtime($i);
            my $w = $worked->{$date};
            my $d = $delta->{$date};
            $ttl_worked += $w;
            $ttl_remain += $d;
            my $worked_width = $ttl_worked * $widthfactor;
            my $remain_width = $ttl_remain * $widthfactor;
            $html .=
                  "<tr><td>$date</td>"
                . "<td align=right>$ttl_remain</td><td><img src=\"$c{misc}{baseurl}images/black.gif\" width=$remain_width height=10>"
                . "<img src=\"$c{misc}{baseurl}images/silver.gif\" width=$worked_width height=10>"
                . "</td></tr>\n";
        }
    }
    else {
        $html .= "<tr><td><b>Insufficient data to produce graph</b></td></tr>\n";
    }

    
    $html .=
          $table_end
        . "<table width=70% border=0>\n"
        . "<tr><td>&nbsp;</td></tr>\n"
        . "<tr><th width=25%>WARNING:</th>"
        . "<td><p style=\"font-size: xx-small\">This is a beta feature. Scale varies depending on data. Scale not displayed."
        . "    This report is very boring until developers begin reporting time in their"
        . "    progress reports. This will take time. No pun intended. Your results may vary."
        . "    This report is still under development. Void where prohibited.</p>"
        . "</td></tr>\n"
        . "</table>\n"
        . page_end('none');
    return $html;
}

sub initialize {
    $cgi = new WorkLog::CGI;
    $dbh = new WorkLog::Database;
}

sub import {
    unless ($inited) {
        initialize;
    }
    $inited++;
}

1;
