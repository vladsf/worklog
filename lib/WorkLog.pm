#
# WorkLog.pm
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
#
package WorkLog;
use warnings;
no warnings 'uninitialized';
use strict;

our $VERSION = sprintf "%d.%03d", q$Revision: 1.21 $ =~ /(\d+)/g;

use Text::Wrap qw(wrap);
use HTML::TreeBuilder;
use HTML::FormatText;
use Net::SMTP;
use POSIX qw(strftime);
use String::Random qw(random_string);
use Digest::MD5 qw(md5_hex);
use LWP::UserAgent;
use WorkLog::Database;
use WorkLog::CGI;

# Exporter
    require Exporter;
    use vars qw(%EXPORT_TAGS @ISA @EXPORT_OK);
    @ISA = qw(Exporter);
    use constant FUNCTIONS => qw(
        _absfilename
         all_children_of
         cat_has_tasks
        _children_of
        _conv_catid
        _conv_prio
        _conv_status
         creator_html
        _db_link_file
        _debug
         depends_loop
        _depends_text
        _dev_owns_tasks
        _do_actions
        _do_admin_sb
        _do_modes
        _do_views
        _email_descrip
         error
        _feed_me
         field_hidden
        _find_tid
         get_catname
        _get_cat_owner_id
         get_current_id
        _get_default
        _get_descrip
        _get_hla
        _get_lld
        _get_devid_email
        _get_devid_name
         get_devname
        _get_didhash
         get_email
        _get_fname
        _get_grpldr_email
        _get_grpldrid
        _get_grpldr_name
        _get_key
        _get_list
        _get_ownerid
        _get_owner_name
        _get_prio
         get_taskgrpldr_name
        _get_taskowner_name
        _get_time
         get_title
        _get_txt_category
        _get_txt_dates
        _get_txt_status
         get_status
        _get_txt_version
         grandchildren_of
         has_seen
         htmlify_text
         html_role_assignment
         hyperlink
         is_admin
         is_arch_ready
        _is_developer
        _is_owner
         is_person
        _link_file_html
        _link_file_text
         mail_developer
        _mailformat_newtask
        _mailformat_reqtok
         mailformat_task
         mail_single
         mark_all_no
         mark_seen
        _message_id
         mk_button
        _mk_diff_log
         mk_title
         notify_cat_owner
        _nth
        _owner_html
        _owner_txt
         pad_me
         page_end
         page_start
        _parse_id_key
         percentages
         personlist
         personlist_html
        _print_action
         priority_color
        _priority_ctextualize
        _priority_textualize
        _record_key
        _remove_dups
         sanitize_txt_input
         show_tasks
        _stor_mesg_id
         table_start
         textformat_task
        _trim_ws
        _uniq
         updatetime_html
        _wk_insert_pnote
         wk_insert_progrep
         wk_set_updated
        _wk_update_assby
        _wk_update_assto
         wk_update_cate
        _wk_update_category
        _wk_update_dabso
        _wk_update_dates
         wk_update_descrip
         wk_update_hla
         wk_update_lld
        _wk_update_devtime
        _wk_update_dopti
        _wk_update_dreal
         wk_update_grpldr
        _wk_update_null
        _wk_update_pnote
         wk_update_prio
         wk_update_status
        _wk_update_time
         wk_update_title
         wk_update_version

    );
    BEGIN {
        foreach (FUNCTIONS) {
            my $function = $_;
            $function =~ s/^/_/ unless /^_/;
            no strict 'refs';
            *{$function} = \&{$function};
        }
    }

    my @EXPORTABLE = grep !/^_/, FUNCTIONS;
    %EXPORT_TAGS = (all => [@EXPORTABLE]);
    #Exporter::export_ok_tags('all');
    @EXPORT_OK = @EXPORTABLE;

    foreach (FUNCTIONS) {
        my $function = $_;
        $function =~ s/^/_/ unless /^_/;
        warn "Catalog contains non-existent sub $function"
          unless defined &{$function};
    }

    foreach (@EXPORTABLE) {
        warn "Unable to export $_ because _$_ is not defined", next
          unless defined &{"_$_"};
        no strict 'refs';
        *{$_} = \&{"_$_"};
    }

$Text::Wrap::columns = 72;
my $dbh = new WorkLog::Database;
my $cgi = new WorkLog::CGI;

use WLCONFIG;
use vars qw(%c);
*c = \%WLCONFIG::conf;

my $url = $cgi->url( -absolute => 1 );

# {
#     my %type = ();
#     sub _assign_type {
#         my $name = shift;
#         unless (%type) {
#             my $statement = 'SELECT name, id FROM assign_types';
#             my @rows = @{ $dbh->selectall_arrayref($statement) };
#             my @types = ();
#             foreach (@rows) {
#                 push @types, @$_;
#             }
#             %type = @types;
#         }
#         return $type{$name} if exists $type{$name};
#         die "Invalid assign_type, $name, requested";
#     }
# }

{
    # Keep cache of username data
    my %id2username = ();
    my %username2id = ();

    sub _html_role_assignment {
            
        unless (%username2id) {
            # Only load cache first time sub is called
            my $statement =
                  "SELECT id, username"
                . "  FROM user"
                . " WHERE active = 'y'"
                . "   AND developer = 'y'"
                ;
            my $sth = $dbh->prepare($statement);
            $sth->execute();
            while (my ($id, $username) = $sth->fetchrow_array) {
                $id2username{$id} = $username;
                $username2id{$username} = $id;
            }
            $id2username{0} = 'NOBODY';
            $username2id{'NOBODY'} = 0;
        }

        my ($title, $formvar, $oldval, $date) = @_;
        my $html = 
            "<tr valign=\"baseline\"><th width=\"35%\" align=\"right\">$title</th>\n"
          . "<td><input type=\"hidden\" name=\"old_$formvar\" value=\"$oldval\">"
          . "<select style=\"width: 100px\" name=\"new_$formvar\">\n"
          ;
        foreach my $un (sort keys %username2id) {
            my $sel = ($username2id{$un} == $oldval) ? ' selected' : '';
            $html .= "<option value=\"$username2id{$un}\"$sel>$un</option>\n";
        }
        $html .= "</select></td>\n<td>";
        if ($date eq 'n/a') {
            $html .= "&nbsp;";
        }
        elsif ($date) {
            my ($short_date) = $date =~ /, (.*?),/;
            $html .= "<abbr title=\"$date\">$short_date</abbr>";
        }
        else {
            $html .= "&nbsp;";
        }
        $html .= "</td>\n<td align=\"center\">";
        if ($date ne 'n/a') {
            if ($date) {
                $html .=
                    "<input type=\"hidden\" name=\"old_mark_date_$formvar\" value=\"set\">"
                    . "<input type=\"checkbox\" name=\"mark_date_$formvar\" value=\"set\" checked>\n";
            }
            else {
                $html .=
                    "<input type=\"hidden\" name=\"old_mark_date_$formvar\" value=\"clear\">"
                    . "<input type=\"checkbox\" name=\"mark_date_$formvar\" value=\"set\">\n";
            }
        }
        else {
            $html .= '&nbsp;';
        }
        $html .= "</td>\n";
        $html .= "</tr>\n";
        return $html;
    }
}

sub _updatetime_html {
    my (
        $tid,
        $cuid,           # Current users ID
        $statement,
        $sth,
        $html,
        @assignees,      # List of ID's assigned to this $tid
        $assigned,       # Boolean, is $cuid in @assignees
        $worked,         # Hours $cuid workedd on $tid so far
        $remain,         # Hours remaining on $tid for $cuid
        $updated,        # Last time they updated this information
    ) = ();

    $tid       = $cgi->param('tid');
    $cuid      = _get_current_id;
    $statement = "SELECT SUM(hrs_worked), MAX(recorded)"
        . "           FROM timelog"
        . "          WHERE task_id = ?"
        . "            AND dev_id  = ?"
        ;
    $sth = $dbh->prepare($statement);
    $sth->execute($tid, $cuid);
    ($worked, $updated) = $sth->fetchrow_array;

    $statement = "SELECT SUM(estimate_delta)"
        . "           FROM timelog"
        . "          WHERE task_id = ?"
        ;
    $sth = $dbh->prepare($statement);
    $sth->execute($tid);
    ($remain) = $sth->fetchrow_array;
    $remain ||= 0;

    $statement = "SELECT developer, designer, coderev1, coderev2, qa"
        . "           FROM tasks"
        . "          WHERE id = ?"
        ;
    $sth = $dbh->prepare($statement);
    $sth->execute($tid);
    @assignees = $sth->fetchrow_array;
    $assigned = 1 if grep {$cuid == $_} @assignees;

    $html .=
          "<table width=80% border=0>\n"
        . "<tr><th align=right width=25%>&nbsp;</th>\n"
        . "<td width=5%>&#160;</td>\n"
        . "<td width=70%>&nbsp;</td></tr>\n"
        ;

    if (defined $worked) {
        # The $cuid has done work on this $tid in the past. Regardless of whether they
        # are assigned to it now or not, they will be permitted to update this information.

        $html .=
              "<tr><th align=right valign=top>Current Status</th><td></td>"
            . "<td valign=top>As of your last reported time ($updated), you have worked <b>$worked</b> hour" . ($worked == 1 ? '':'s') . " on this task."
            . "    Approximately <b>$remain</b> hour" . ($remain == 1 ? '':'s') . " of work remain" . ($remain == 1 ? 's':'') . "."
            . "</td></tr><tr><td colspan=3>&nbsp;</td></tr>\n"
            . "<tr><th align=right valign=top>Hours Worked<br><br>"
            . "<input type=text name=worked value=\"0\" size=8 autocomplete=\"off\" "
            . "onChange=\"if($remain>worked.value){remain.value=$remain-worked.value;}else{remain.value=0}\"></td><td></td>"
            . "<td valign=top><small>Report hours, if any, you have worked on this task since you last updated"
            . "    this information (positive integers only). If you're simply updating the estimate of time"
            . "    remaining, please leave this value zero.</small>"
            . "</td></tr><tr><td colspan=3>&nbsp;</td></tr>"
            . "<tr><th align=right valign=top>Estimated Hours Remaining<br><br>"
            . "<input type=text name=remain value=\"\" size=8 autocomplete=\"off\"></td><td></td>"
            . "<td valign=top><small>As of now, estimate how many more hours of work you will need to"
            . " complete this task. If you enter hours worked above, this value will"
            . " be calculated automatically based on your last estimate. Adjust this as necessary."
            ;
    }
    else {
        unless ($assigned) {
            # The $cuid has not done any work on this $tid before *and* they are not
            # assigned for any roles. They will receive a warning just in case they
            # made a mistake.
            $html .=
                  "<tr><th align=right valign=top><font color=\"#f00\">WARNING !!</font></th><td></td>"
                . "<td valign=top>You do not appear to be assigned to any roles for this task. If you made"
                . "    a mistake, click <a href=\"$c{misc}{baseurl}?tid=$tid\">here</a>. If you need to report"
                . "    time on this task anyway, proceed below."
                . "</td></tr><tr><td colspan=3>&nbsp;</td></tr>\n"
                ;
        }
        $html .=
              "<tr><th align=right valign=top>Hours Worked<br><br>"
            . "<input type=text name=worked value=\"0\" size=8 autocomplete=\"off\" "
            . "onChange=\"if($remain>worked.value){remain.value=$remain-worked.value;}else{remain.value=0}\"></td><td></td>"
            . "<td valign=top><small>Report any hours you have already worked on this task (positive"
            . " integers only, zero included). If you are just setting your initial work estimate,"
            . " leave this value zero.</small></td></tr><tr><td colspan=3>&nbsp;</td></tr>"
            . "<tr><th align=right valign=top>Estimated Hours Remaining<br><br>"
            . "<input type=text name=remain value=\"\" size=8 autocomplete=\"off\"></td><td></td>"
            . "<td valign=top><small>Excluding the hours you may have already worked on this task (above),"
            . " estimate how many more hours of work you will need to complete your role(s) in this task."
            ;
    }

    $html .=
          " You must provide a positive integer of hours even if"
        . " it is zero (i.e., you're done working on it).</small>"
        . "</td></tr><tr><td colspan=3>&nbsp;</td></tr>"
        . "</table>"
        . "<input type=hidden name=lastremain value=\"$remain\">"
        ;
    return $html;
}

sub _percentages {
    my ($progress, $remaining, $width) = @_;
    my $wdone = 0;
    my $wremain = 0;
    $width = 240 unless defined $width && $width > 0;
    my $total = $progress + $remaining;
    $wdone  = sprintf "%.0f", $progress  / $total * $width if $total > 0;
    $wremain = $width - $wdone;

    return ($wdone, $wremain);
}

sub _page_start {
    my $subtitle = shift;

    my $page = $cgi->header;
    $page .=
            "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\">\n"
          . "<html><head>\n"
          . "<title>WorkLog: $subtitle</title>\n"
          . "$c{misc}{style}\n"
          . "<script language=\"JavaScript1.1\">\n"
          . "function openwindow(location) {\n"
          . "      uploadWindow = window.open(location, \"UploadFile\", \"scrollbars,resizable\");\n"
          . "      return;\n"
          . "}\n"
          . "//-->\n"
          . "</script>\n"
          . "</head><body background=\"$c{images}{bkg}{src}\">\n"
          ;

    return $page;
}

sub _table_start {
    my $type = shift;
    my $rarg = shift;

    my $html =
            # outer box
            "<table width=\"100%\" cellpadding=0 cellspacing=0 border=0>\n"
          . "<tr><td align=center valign=top>\n"
            # curved borders
          . "<table width=\"100%\" cellpadding=0 cellspacing=0 border=0 bgcolor=\"$c{color}{white}\">\n"
          . "<tr>\n"
          . "<td valign=top><img src=\"$c{images}{ul}{src}\" height=\"$c{images}{ul}{height}\" width=\"$c{images}{ul}{width}\"></td>\n"
          . "<td>&#160;</td>\n"
          . "<td valign=top align=right><img src=\"$c{images}{ur}{src}\" height=\"$c{images}{ur}{height}\" width=\"$c{images}{ur}{width}\"></td></tr>\n"
          . "<tr><td valign=top colspan=3>\n"
            # Does this actually do anything?
          . "<table width=\"100%\" cellpadding=6 cellspacing=0 border=0 bgcolor=\"$c{color}{white}\">\n"
          . "<tr><td width=\"100%\">\n"
            # main boxy
          . "<table width=\"100%\" cellpadding=0 cellspacing=0 border=0 bgcolor=\"$c{title}{bg_anti}\">\n"
          . "<tr><td width=10>\n"
          ;

    if ( $type eq 'normal' ) {
        $html .= "&#160;</td><td><form method=\"post\" action=\"\">\n";
        $html .= _do_views $rarg->{view};
    }
    elsif ( $type eq 'minimal' ) {
        $html .=
            "&#160;\n"
          . "</td><td>&#160;\n"
          ;
    }

    $html .= "</form></td></tr>\n";

    #if ( $type eq 'normal' && $rarg->{actions} ) {
    if (                      $rarg->{actions} ) {
        $html .= "<tr><td width=10>&#160;</td><td valign=bottom>\n";

        $html .= _do_actions $rarg;
    }
    else {
        $html .=
            "<tr>\n"
          . "<td align=right>\n"
          . "&#160;\n"
          . "</td><td>\n"
          . "&#160;\n"
          ;
    }

    $html .=
            "</td></tr>\n"
          . "</table>\n"
          . "<hr width=\"100%\"></td>\n"
          . "<td valign=top align=right>\n"
          . "<a href=\"$c{misc}{baseurl}\"><img src=\"$c{images}{logo}{src}\" height=\"$c{images}{logo}{height}\" width=\"$c{images}{logo}{width}\" alt=\"WorkLog Frontpage\" border=0></a>\n"
          . "</td></tr>\n"
          . "<td valign=top>\n"
          ;

    return $html;
}

sub _page_end {
    my $mode = shift;

    my $html =
            "<br>\n"
          . "</td>\n"
          . "<td valign=top align=right>\n"
          ;

  # if ( $mode ne 'none' ) {
    if ( 1               ) {
        $html .= "<table>\n";
        $html .= _do_modes $mode;
        $html .= _do_admin_sb() if _is_admin;
        $html .= "</table>\n";
    }


    $html .=
            "</td></tr></table>\n"
          . "</td></tr>\n"
          . "<tr>\n"
          . "<td valign=bottom><img src=\"$c{images}{ll}{src}\" height=\"$c{images}{ll}{height}\" width=\"$c{images}{ll}{width}\"></td>\n"
          . "<td valign=middle>\n"
          . "<font size=\"-2\">WorkLog v$c{misc}{version} <br>"
          . "&nbsp;&nbsp;&copy; 2004&#160; Andrew Sweger &lt;<a href=\"mailto:yDNA\@perlocity.org\">yDNA\@perlocity.org</a>&gt; and <a href=\"http://addnorya.com/\">Addnorya</a><br>\n"
          . "&nbsp;&nbsp;&copy; 2003&#160; Matt Wagner &lt;<a href=\"mailto:matt\@mysql.com\"><font color=\"$c{color}{mysqlblu}\">matt\@mysql.com</font></a>&gt; and <a href=\"http://www.mysql.com/\"><font color=\"$c{color}{mysqlblu}\">MySQL AB</font></a></font></td>\n"
          . "<td valign=bottom align=right><img src=\"$c{images}{lr}{src}\" height=\"$c{images}{lr}{height}\" width=\"$c{images}{lr}{width}\"></td></tr>\n"
          . "</table>\n"
          . "</td></tr></table>\n"
          . "</body></html>\n"
          ;

    return $html;
};

sub _mk_button {
    my $label = shift;
    my $link  = shift;
    my $confirm = shift;

    #    (!defined $color)? "#6699ff" : $color;
    my $color = "#f0f0f0";
    my $button = '';

    if (defined $confirm) {
        $button = "<input type=button onClick=\"if (confirm(&#39;$confirm&#39;)) location = '$link';\" style=\"background-color: $color;\" value=\"$label\">";
    }
    else {
        $button = "<a href=\"$link\"><input type=button onClick=\"window.location = '$link'\" style=\"background-color: $color;\" value=\"$label\"></a>";
    }

    return $button;
}

sub _mk_title {
    my $text = shift;
    my $big  = shift;

    my $size = ($big) ? $c{title}{size_big} : $c{title}{size_small};

    my $html =
            "<table cellpadding=0 cellspacing=1 width=\"100%\" border=0 bgcolor=\"$c{color}{mysqlblu}\">\n"
          . "<tr><td align=center valign=center>\n"
          . "<table cellpadding=1 cellspacing=1 width=\"100%\" border=0 bgcolor=\"$c{color}{ltblue}\">\n"
          . "<!--<tr><td><font face=\"$c{title}{face}\" size=\"+$size\" color=\"$c{title}{txt}\">&#160;$text</font></td></tr></table>-->\n"
          . "<tr><td><font size=\"+$size\" color=\"$c{title}{txt}\">&#160;$text</font></td></tr></table>\n"
          . "</td></tr></table>\n"
          ;

    return $html;
}

sub _priority_color {
    my $prio = shift;

    my $prio_save = $prio;
    $prio = $c{prio_clr}{complete} if ( $prio_save == 0 );
    $prio = $c{prio_clr}{verylow}  if ( $prio_save > 0 && $prio_save < 40 );
    $prio = $c{prio_clr}{low}      if ( $prio_save >= 40 && $prio_save < 60 );
    $prio = $c{prio_clr}{medium}   if ( $prio_save >= 60 && $prio_save < 75 );
    $prio = $c{prio_clr}{high}     if ( $prio_save >= 75 && $prio_save < 90 );
    $prio = $c{prio_clr}{veryhigh} if ( $prio_save >= 90 );

    return $prio;
}

sub _priority_textualize {
    my $prio = shift;

    my $prio_save = $prio;
    $prio = $c{prio_txt}{complete} if ( $prio_save == 0 );
    $prio = $c{prio_txt}{verylow}  if ( $prio_save > 0 && $prio_save < 40 );
    $prio = $c{prio_txt}{low}      if ( $prio_save >= 40 && $prio_save < 60 );
    $prio = $c{prio_txt}{medium}   if ( $prio_save >= 60 && $prio_save < 75 );
    $prio = $c{prio_txt}{high}     if ( $prio_save >= 75 && $prio_save < 90 );
    $prio = $c{prio_txt}{veryhigh} if ( $prio_save >= 90 );

    return $prio;
}

sub _priority_ctextualize {
    my $prio  = shift;
    my $cprio = shift;

    return "<font color=\"$cprio\"><b>$prio</b></font>";
}

sub _pad_me {
    my $pad_type = shift;
    my $pad_str  = shift;

    my $len = length("$pad_str");
    if ( $len <= $c{strlen}{"$pad_type"} ) {
        my $diff_len = $c{strlen}{"$pad_type"} - $len;
        $pad_str .= "&#160;" x ( $diff_len + 1 ) if ( $pad_type ne 'etitle' );
        $pad_str .= " " x      ( $diff_len + 1 ) if ( $pad_type eq 'etitle' );
    }
    else {
        my $form = '<' x ( $c{strlen}{"$pad_type"} - 3 ) . '...';
        $^A = "";
        $pad_str =~ s/-/_/g;
        $pad_str =~ s/\s/^/g;
        formline "^$form", $pad_str;
        $pad_str = $^A;
        $pad_str =~ s/_/-/g;
        $pad_str =~ s/\^/&\#160\;/g if ( $pad_type ne 'etitle' );
        $pad_str =~ s/\^/ /g if ( $pad_type eq 'etitle' );
    }

    return $pad_str;
}

sub _error {
    my $err_msg = shift;

    my $ptitle = "Error";

    my $html_page = _page_start $ptitle;
    $html_page .= _table_start 'minimal', {'actions' => 0};
    $html_page .= _mk_title $ptitle;
    # my $d = Data::Dumper->new( [ $cgi->param ] );
    # my $dd = $d->Dump;
    my $dd = $cgi->Dump;

    $html_page .=
            "<table>\n"
          . "<tr><th valign=top align=left><font color=\"$c{color}{red}\" size=\"+1\">$ptitle</font></th></tr>\n"
          . "<tr><td valign=top>$err_msg<br><br><pre>$dd</pre></td></tr></table>\n"
          ;

    $html_page .= _page_end '';

    print $html_page;

    $dbh->disconnect;
    exit;
}

sub _message_id {
    my $hostname = shift;

    my $time = strftime '%j%H%M%S', localtime;
    my $n64 = "." x 64;
    my $str64 = random_string($n64);

    my $mid = '<' . $time . '.';
    $mid .= md5_hex("$time$str64") . "\@$hostname>";

    return $mid;
}

sub _email_descrip {
    my $descrip = shift;

    $descrip = wrap( "\t", "\t", $descrip );

    return $descrip;
}

sub _depends_loop {
    my (@tasks) = @_;
    eval {
        local $SIG{'__DIE__'};
        _all_children_of(@tasks);
    };
    return 1 if $@;
    return 0;
}

sub _all_children_of {
    my ($first, @others) = @_;
    @others = () unless @others;
    my @stack = ();
    my %seen  = ();
    push @stack, _children_of($first), @others;
    while (@stack) {
        my $next = pop @stack;
        die "Circular reference under task $first" if $next == $first;
        $seen{$next}++;
        push @stack, _children_of $next;
    }
    return keys %seen;
}

sub _uniq {
    my (@list) = @_;
    my (%keys) = map {$_, 1} @list;
    return sort {$a <=> $b} keys %keys;
}

sub _grandchildren_of {
    my ($grandparent) = @_;
    my @parents = _children_of $grandparent;
    my @grandchildren = ();
    foreach (@parents) {
        my @kids = _all_children_of $_;
        push @grandchildren, @kids;
    }
    return _uniq @grandchildren;
}

sub _children_of {
    my ($parent) = @_;
    my $statement = 'SELECT child FROM depends WHERE parent = ?';
    my $sth = $dbh->prepare($statement);
    $sth->execute($parent);
    my @children = ();
    while ( my ($child) = $sth->fetchrow_array ) {
        push @children, $child;
    }
    return @children;
}

sub _owner_txt {
    my $owner     = shift;
    my $enteredby = shift;

    my $statement = "SELECT username FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($owner);

    my @ret = $sth->fetchrow_array;

    return $ret[0];
}

sub _owner_html {
    my $owner     = shift;
    my $enteredby = shift;
    my $tid       = shift;

    my $statement = "SELECT username, email FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($owner);

    my @ret = $sth->fetchrow_array;

    return "<a href=\"forms.pl?form=reassign&tid=$tid\">$ret[0]</a>";
}

sub _creator_html {
    my $owner     = shift;

    my $statement = "SELECT username FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($owner);

    my @ret = $sth->fetchrow_array;

    return "$ret[0]";
}

sub _uid2username {
    my $id = shift;

    my $statement = "SELECT username FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($id);

    my @ret = $sth->fetchrow_array;

    return $ret[0];
}

sub _uid2username_html {
    my $grpldr = shift;
    my $tid    = shift;

    my $username = _uid2username($grpldr);

    return "<a href=\"forms.pl?form=reassign&tid=$tid\">$username</a>";
}

sub _depends_text {
    my ($tid, $kind) = @_;
    my @depends      = ();
    my $relative     = $kind eq 'parent' ? 'child' : 'parent';
    my $statement    = "SELECT t.id, t.title FROM tasks t, depends d WHERE d.$relative = ? AND d.$kind = t.id";
    my $sth          = $dbh->prepare($statement);
    $sth->execute($tid);
    while ( my ($id, $title) = $sth->fetchrow_array ) {
        push @depends, sprintf( "%4d %s\n", $id, $title );
    }

    return @depends;
}

sub _personlist {
    my ($tid, $kind) = @_;
    my $statement = '';

    if ($kind eq 'developer') {
        $statement =
          "SELECT u.username FROM tasks t, user u WHERE "
          . "t.id = ? AND t.developer = u.id";
    }
    elsif ($kind eq 'observers') {
        $statement = 
            "SELECT u.username"
          . "  FROM observers o, user u"
          . " WHERE o.dev_id = u.id"
          . "   AND o.task_id = ?"
          ;
    }
    else {
        error ("personlist does not know how to handle kind $kind");
    }

    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    my @plist;
    while ( my @arr = $sth->fetchrow_array ) {
        push @plist, $arr[0];
    }

    if ( scalar @plist == 0 ) {
        push @plist, '';
    }

    return @plist;
}

sub _personlist_email {
    my ($tid, $kind) = @_;
    my $statement = '';

    if ($kind eq 'developer') {
        $statement =
          "SELECT u.email FROM tasks t, user u WHERE "
          . "t.id = ? AND t.developer = u.id";
    }
    elsif ($kind eq 'observers') {
        $statement = 
            "SELECT u.email"
          . "  FROM observers o, user u"
          . " WHERE o.dev_id = u.id"
          . "   AND o.task_id = ?"
          ;
    }
    else {
        error ("personlist does not know how to handle kind $kind");
    }

    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    my @plist;
    while ( my @arr = $sth->fetchrow_array ) {
        push @plist, $arr[0];
    }

    if ( scalar @plist == 0 ) {
        push @plist, '';
    }

    return @plist;
}

sub _personlist_html {
    my $tid  = shift;
    my $kind = shift;

    my @personlist = _personlist($tid, $kind);
    my @plist;
    for my $person (@personlist) {
        push @plist, "<a href=\"forms.pl?form=reassign&tid=$tid\">$person</a>";
    }

    if ( scalar @plist == 0 ) {
        push @plist, "<a href=\"forms.pl?form=reassign&tid=$tid\">Nobody</a>";
    }

    return @plist;
}

sub _remove_dups {
    my $arr = shift;

    my %hash = map {$_, 1} grep {defined $_ && $_ ne ''} @$arr;
    my @retarr = keys %hash;

    return \@retarr;
}

########################################################################
######## Figure out who is logged in right now
sub _get_current_id {
    return $ENV{REMOTE_USER};
}

########################################################################
######## Hyperlink Controls routines

sub _is_admin {
    my $did = shift || _get_current_id;

    my $statement = "SELECT admin FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($did);

    my @res = $sth->fetchrow_array;

    return ( defined $res[0] and $res[0] eq 'y' ) ? 1 : 0;
}

# a person is not a non-human
sub _is_person {
    my $did = shift || _get_current_id;

    my $statement = "SELECT id FROM user WHERE id = ? AND human = 'y'";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($did);

    return ( defined $sth->fetchrow_array ) ? 1 : 0;
}

sub _is_owner {
    my $tid = shift;
    my $did = shift;

    my $statement = "SELECT owner, enteredby FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    my @res = $sth->fetchrow_array;

    return ( $res[0] == $did || $res[1] == $did ) ? 1 : 0;
}

sub _is_developer {
    my $tid = shift;
    my $did = shift;

    my $statement =
      "SELECT dev_id FROM assignments WHERE task_id = ? AND dev_id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute( $tid, $did );

    my ($res) = $sth->fetchrow_array;

    return ( $res eq $did ) ? 1 : 0;
}

sub _find_tid {
    my $fid = shift;

    my $statement =
      "SELECT a.task_id FROM file_lut fl, amendments a WHERE "
      . "fl.amend_id = a.id AND fl.file_id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($fid);

    return ( $sth->fetchrow_array );
}

sub _do_actions {
    my $rarg = shift;

    my $html_return = '';

    my %topbar = (
        owner => [
           #{ name => 'Progress Notes & Status', form => 'forms.pl?form=addprogrep',  tid => 1, arch => 0 },
           #{ name => 'Priority',                form => 'forms.pl?form=chprio',      tid => 1, arch => 0 },
           #{ name => 'Re-Assign',               form => 'forms.pl?form=reassign',    tid => 1, arch => 0 },
            { name => 'Add New Task',            form => 'forms.pl?form=addtask',     tid => 0, arch => 0 },
           #{ name => 'Observe',                 form => 'forms.pl?form=observ',      tid => 1, arch => 0 },
            { name => 'Delete This Task',        form => 'forms.pl?form=delete',      tid => 1, arch => 0 },
            { name => 'Request Copy via Email',  form => 'forms.pl?form=reqcopyform', tid => 1, arch => 0 },
            { name => 'Request Copy via Email',  form => 'forms.pl?form=reqcopyform', tid => 1, arch => 1 },
            { name => 'Re-Activate',             form => 'forms.pl?form=reactive',    tid => 1, arch => 1 },
            { name => 'Burndown Report',         form => 'forms.pl?form=burndown',    tid => 1, arch => 0 },
        ],
        developer => [
            { name => 'Progress Notes & Status', form => 'forms.pl?form=addprogrep',  tid => 1, arch => 0 },
            { name => 'Priority',                form => 'forms.pl?form=chprio',      tid => 1, arch => 0 },
            { name => 'Re-Assign',               form => 'forms.pl?form=reassign',    tid => 1, arch => 0 },
            { name => 'Delete',                  form => 'forms.pl?form=delete',      tid => 1, arch => 0 },
            { name => 'Request Copy via Email',  form => 'forms.pl?form=reqcopyform', tid => 1, arch => 0 },
            { name => 'Re-Activate',             form => 'forms.pl?form=reactive',    tid => 1, arch => 1 },
        ],
        observer => [
           #{ name => 'Observe',                 form => 'forms.pl?form=observ',      tid => 1, arch => 0 },
            { name => 'Request Copy via Email',  form => 'forms.pl?form=reqcopyform', tid => 1, arch => 0 },
            { name => 'Request Copy via Email',  form => 'forms.pl?form=reqcopyform', tid => 1, arch => 1 },
        ],
        fund => [
            { name => 'Add New Task',            form => 'forms.pl?form=addtask',     tid => 0, arch => 0 },
           #{ name => 'Add New Task via Email',  form => 'forms.pl?form=reqnewform',  tid => 0, arch => 0},
        ],
        main => [
            { name => 'Add New Task',            form => 'forms.pl?form=addtask',     tid => 0, arch => 0 },
            { name => 'Report Generator',        form => 'report.pl',                 tid => 0, arch => 0 },
           #{ name => 'Add New Task via Email',  form => 'forms.pl?form=reqnewform',  tid => 0, arch => 0},
        ],
    );

    if ( $rarg->{fund} ) {
        $html_return = _print_action($topbar{fund}, 0, $rarg->{vflag});
    }
    elsif ( $rarg->{main} ) {
        $html_return = _print_action($topbar{main}, 0, $rarg->{vflag});
    }
    else {

        #    if (_is_owner $rarg->{tid}, $rarg->{did}) {
        $html_return =
          _print_action($topbar{owner}, $rarg->{tid}, $rarg->{vflag});

        #     }
        #     elsif (_is_developer $rarg->{tid}, $rarg->{did}) {
        #       $html_return = _print_action $topbar{developer}, $rarg->{tid}, $rarg->{vflag};
        #     }
        #     else {
        #       $html_return = _print_action $topbar{observer}, $rarg->{tid}, $rarg->{vflag};
        #     }
    }

    return $html_return;
}

sub _print_action {
    my $links = shift;
    my $tid   = shift;
    my $view  = shift || '';

    my $html_return .= "<font face=\"$c{title}{face}\"><table><tr>";

    foreach my $ptr ( @$links ) {
        if ( $view eq 'archived' ) {
            if ( $ptr->{arch} ) {
                if ( $ptr->{tid} ) {
                    $html_return .= "<td>" . _mk_button( "$ptr->{name}",
                        "$ptr->{form}&tid=$tid" ) . "</td>\n";
                }
                else {
                    $html_return .= "<td>" . _mk_button( "$ptr->{name}",
                        "$ptr->{form}" ) . "</td>\n";
                }
            }
        }
        else {
            if ( !$ptr->{arch} ) {
                if ( $ptr->{tid} ) {
                    $html_return .= "<td>" . _mk_button( "$ptr->{name}",
                        "$ptr->{form}&tid=$tid" ) . "</td>\n";
                }
                else {
                    $html_return .= "<td>" . _mk_button( "$ptr->{name}",
                        "$ptr->{form}" ) . "</td>\n";
                }
            }
        }
    }
    $html_return .= "</tr></table></font>";
    return $html_return;
}

sub _do_modes {
    my $mode = shift;

    my $html_return =
          "<tr>\n"
        . "<td align=right valign=middle colspan=2>\n"
        . "<form method=get action=\"$c{misc}{baseurl}index.pl\" name=\"SearchWorkLog\">\n"
        . "<input type=text name=search size=15 value=\"Search WorkLog\" onFocus=\"if (document.SearchWorkLog.search.value == 'Search WorkLog') document.SearchWorkLog.search.value = '';\" onBlur=\"if (document.SearchWorkLog.search.value == '') document.SearchWorkLog.search.value = 'Search WorkLog';\">\n"
        . "</form></td></tr>\n"
        . "<tr>\n"
        . "<td colspan=2 align=right>\n"
        . "<select style=\"width: 120px\" name=\"cat_id\" onChange=\"window.location.href=this.options[this.selectedIndex].value\">\n"
        ;

    my $catname   = $cgi->param('catname') || '';
    my $statement = "SELECT id, name FROM categories ORDER BY name";
    my $sth = $dbh->prepare($statement);
    $sth->execute;

    while ( my $res = $sth->fetchrow_arrayref ) {
        my $sel = ( $res->[1] eq $catname ) ? " selected" : "";
        $html_return .= "<option value=\"$c{misc}{baseurl}$res->[1]/\"$sel>$res->[1]</option>\n";
    }

    $html_return .=
          "</select></td></tr>\n"
        . "<tr><td colspan=2><hr></td></tr>\n"
        ;

    # Time Estimates (Virutal Tasks), by Version, et al.
    $html_return .=
          "<tr><td colspan=2 align=left>\n"
        . "Time Estimates:"
        . "</td></tr>"
        . "<tr><td colspan=2 align=right>\n"
        . "<select style=\"width: 120px\" name=\"virtual_task\" onChange=\"window.location.href=this.options[this.selectedIndex].value\">\n"
        . "<option value=\"\">by Version</option>\n"
        ;

        foreach my $item ( sort keys %{ $c{misc}{versions} } ) {
            my $greatestver = ( @{ $c{misc}{versions}{$item} }[0] );
            $html_return .= "<option value=\"$c{misc}{baseurl}index.pl?virtual=version:$item-$greatestver\">$item</option>\n";
            foreach my $itemver ( @{ $c{misc}{versions}{$item} } ) {
                $html_return .= "<option value=\"$c{misc}{baseurl}index.pl?virtual=version:$item-$itemver\">&nbsp;&nbsp;&nbsp;&nbsp;$itemver</option>\n";
            }
        }

    # TE by Category
    $html_return .=
          "</select><br>\n"
        . "<select style=\"width: 120px\" name=\"virtual_task\" onChange=\"window.location.href=this.options[this.selectedIndex].value\">\n"
        . "<option value=\"\">by Category</option>\n"
        ;

        $statement = "SELECT DISTINCT category FROM categories ORDER BY category";
        $sth = $dbh->prepare($statement);
        $sth->execute;
        while ( my ($category) = $sth->fetchrow_array ) {
            $html_return .= "<option value=\"$c{misc}{baseurl}index.pl?virtual=category:$category\">$category</option>\n";
        }
        $sth->finish;

    # TE by Queue
    $html_return .=
          "</select><br>\n"
        . "<select style=\"width: 120px\" name=\"virtual_task\" onChange=\"window.location.href=this.options[this.selectedIndex].value\">\n"
        . "<option value=\"\">by Queue</option>\n"
        ;

        $statement = "SELECT DISTINCT queue FROM categories ORDER BY queue";
        $sth = $dbh->prepare($statement);
        $sth->execute;
        while ( my ($queue) = $sth->fetchrow_array ) {
            $html_return .= "<option value=\"$c{misc}{baseurl}index.pl?virtual=queue:$queue\">$queue</option>\n";
        }
        $sth->finish;

    # TE by Status
    $html_return .=
          "</select><br>\n"
        . "<select style=\"width: 120px\" name=\"virtual_task\" onChange=\"window.location.href=this.options[this.selectedIndex].value\">\n"
        . "<option value=\"\">by Status</option>\n"
        ;

        $statement = "SELECT id, status FROM status ORDER BY id";
        $sth = $dbh->prepare($statement);
        $sth->execute;
        while ( my ($id, $status) = $sth->fetchrow_array ) {
            $html_return .= "<option value=\"$c{misc}{baseurl}index.pl?virtual=status:$id\">$status</option>\n";
        }
        $sth->finish;

    # TE by Supervisor
    $html_return .=
          "</select><br>\n"
        . "<select style=\"width: 120px\" name=\"virtual_task\" onChange=\"window.location.href=this.options[this.selectedIndex].value\">\n"
        . "<option value=\"\">by Supervisor</option>\n"
        ;

        $statement = "SELECT id, username FROM user WHERE grpldr = 'y' ORDER BY username";
        $sth = $dbh->prepare($statement);
        $sth->execute;
        while ( my ($id, $username) = $sth->fetchrow_array ) {
            $html_return .= "<option value=\"$c{misc}{baseurl}index.pl?virtual=grpldr:$id\">$username</option>\n";
        }
        $sth->finish;

    # TE by Developer
    $html_return .=
          "</select><br>\n"
        . "<select style=\"width: 120px\" name=\"virtual_task\" onChange=\"window.location.href=this.options[this.selectedIndex].value\">\n"
        . "<option value=\"\">by Developer</option>\n"
        ;

        $statement =
              "SELECT id, username"
            . "  FROM user"
            . " WHERE human = 'y'"
            . "   AND active = 'y'"
            . " ORDER BY username"
            ;
        $sth = $dbh->prepare($statement);
        $sth->execute;
        while ( my ($id, $username) = $sth->fetchrow_array ) {
            $html_return .= "<option value=\"$c{misc}{baseurl}index.pl?virtual=developer:$id\">$username</option>\n";
        }
        $sth->finish;

    $html_return .=
          "</select></td></tr>\n"
        . "<tr><td colspan=2><hr></td></tr>\n"
        ;

    # SQL query
    $html_return .=
          "<tr><td align=right valign=middle colspan=2>"
        . mk_button ('SQL query', "$c{misc}{baseurl}forms.pl?form=sql")
        . "</td></tr>\n"
        ;

    return $html_return;
}

sub _do_admin_sb {
    my $html_return = '';

    my @admin_sb = (
        { 'name' => 'Category &plusmn', 'form' => 'forms.pl?form=addcat' },
      # { 'name' => 'WKL User &plusmn', 'form' => 'forms.pl?form=adduser' },
    );

    $html_return .= "<tr><td colspan=2><hr></td></tr>\n";
    foreach my $item ( @admin_sb ) {
        $html_return .= "<tr><td colspan=2 align=right>\n";

        $html_return .= _mk_button( "$item->{name}", "$item->{form}" )
          . "</td></tr>";
    }

    return $html_return;
}

sub _do_views {
    my $view = shift;

    my $html_return = '';
    my $aflag = ( $view eq 'archived' ) ? '1' : '0';

    my @params = $cgi->param;

    my $astext_params = '?';

    foreach my $param ( @params ) {
        next if ( $param eq 'catname' );
        $astext_params .= "$param=" . $cgi->param($param) . "&";
    }

    $html_return .= "<font face=\"$c{title}{face}\"><table><tr>";
    $html_return .= "<td>" . _mk_button( "Active List", "index.pl" ) . "</td>";
    $html_return .= "<td>" . _mk_button( "Inactive List", "index.pl?archtask=1" ) . "</td>";
    $html_return .= "<td>"
      . _mk_button( "Current as Text", "index.pl" . "${astext_params}astext=1" )
      . "</td>";
    $html_return .= "</font>";
    $html_return .= "<font face=\"$c{title}{face}\" size=\"-1\">";

    if ($dbh) {
        $html_return .= "<td><select style=\"width: 100px\" name=show_devid onChange=\"window.location.href "
          . "= this.options[this.selectedIndex].value\">\n";
        $html_return .= "<option value=\"index.pl?show_devid=0&archtask=$aflag\">Everybody</option>\n";

        my $sth = $dbh->prepare("SELECT id, username FROM user ORDER BY username");
        $sth->execute;

        my $trigger = 1;
        while ( my ( $id, $name ) = $sth->fetchrow_array ) {
            my $sel = "";
            my $show_devid = $cgi->param('show_devid') || 0;
            if ( ( $trigger && $show_devid == $id ) ) {
                $sel     = " selected";
                $trigger = 0;
            }
            $html_return .= "<option value=\"index.pl?show_devid=$id&archtask=$aflag\"$sel>$name</option>\n";
        }
        $html_return .= "</select></td></tr></table>";
    }
    else {
        $html_return .= "[Error]";
    }

    return $html_return;
}

########################################################################
######## Data Integrity routines

sub _cat_has_tasks {
    my $cat_id = shift;

    my $statement = "SELECT id FROM tasks WHERE cat_id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($cat_id);

    return ( $sth->fetchrow_array ) ? 1 : 0;
}

sub _dev_owns_tasks {
    my $dev_id = shift;

    my $statement = "SELECT id FROM tasks WHERE owner = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($dev_id);

    return ( $sth->fetchrow_array ) ? 1 : 0;
}

sub _show_tasks {
    my $id  = shift;
    my $col = shift;

    my $statement = "SELECT id, title FROM tasks WHERE $col = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($id);

    my $thing = ( $col eq 'owner' ) ? 'person' : 'category';
    my $html  =
            "<b>Unresolved Data Dependency</b>\n"
          . "\n"
          . "<p>This $thing has the following task(s) associated with them. Deleting would\n"
          . "orphan these tasks. Try re-assigning the task(s) before deleting.</p>\n"
          . "<ul>\n"
          ;
    while ( my ( $tid, $title ) = $sth->fetchrow_array ) {
        $html .= "<li><a href=\"$c{misc}{baseurl}index.pl?tid=$tid\">$title</a>\n";
    }

    return $html;
}

########################################################################
######## Visuals routines

sub _mark_all_no {
    my $tid = shift;

    my $statement = "UPDATE visual SET seen = 'n' WHERE task_id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return;
}

sub _mark_seen {
    my $tid = shift;
    my $did = shift;

    my $statement = "SELECT seen FROM visual WHERE task_id = ? AND dev_id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $tid, $did );

    my $result = $sth->fetchrow_array || '';
    if ( $result eq '' ) {
        $statement = "INSERT INTO visual (task_id, dev_id, seen) VALUES (?,?,?)";
        $sth = $dbh->prepare($statement);
        $sth->execute( $tid, $did, 'y' );
        return;
    }
    elsif ( $result eq 'n' ) {
        $statement = "UPDATE visual SET seen = 'y' WHERE task_id = ? AND dev_id = ?";
        $sth = $dbh->prepare($statement);
        $sth->execute( $tid, $did );
        return;
    }

    return;
}

sub _has_seen {
    my $tid = shift;
    my $did = shift;

    my $statement = "SELECT seen FROM visual WHERE task_id = ? AND dev_id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $tid, $did );

    my $result = $sth->fetchrow_array || '';
    if ( $result eq '' || $result eq 'n' ) {
        return 0;
    }
    elsif ( $result eq 'y' ) {
        return 1;
    }
}

########################################################################
######## Upload file routines

sub _link_file_html {
    my $npid = shift;

    my $html = '';

    if ( $npid eq '' ) {
        return;
    }
    else {
        my $statement = "SELECT file_id FROM file_lut WHERE amend_id = ?";
        my $sth       = $dbh->prepare($statement);
        $sth->execute($npid);

        $html .= "<blockquote>\n";
        while ( my ($file_id) = $sth->fetchrow_array ) {
            $statement = "SELECT filename FROM files WHERE id = ?";
            my $sth2 = $dbh->prepare($statement);
            $sth2->execute($file_id);

            my ($filename) = $sth2->fetchrow_array;

            $html .=
                "<table cellpadding=1 cellspacing=1 width=\"50%\" border=0 bgcolor=\"$c{color}{grey}\">\n"
              . "<tr><td>\n"
              . "<table cellpadding=2 cellspacing=0 width=\"100%\" border=0 bgcolor=\"$c{color}{fgold}\">\n"
              . "<tr><td>\n"
              . "<table cellpadding=0 cellspacing=0 border=0>\n"
              . "<tr><th align=right>&#160;Attachment&#160;&#160;</th>\n"
              . "<td><a href=\"$c{misc}{baseurl}forms.pl?form=fid&fid=$file_id\">$filename</a></td></tr>\n"
              . "</table>\n"
              . "</td></tr></table>\n"
              . "</td></tr></table><p>\n"
              ;
        }

        $html .= "</blockquote>\n";

        return $html;
    }
}

sub _link_file_text {
    my $npid = shift;

    my $text;

    if ( $npid eq '' ) {
        return;
    }
    else {
        my $statement = "SELECT file_id FROM file_lut WHERE amend_id = ?";
        my $sth       = $dbh->prepare($statement);
        $sth->execute($npid);

        $text .= "<blockquote>\n";
        while ( my ($file_id) = $sth->fetchrow_array ) {
            $statement = "SELECT filename FROM files WHERE id = ?";
            my $sth2 = $dbh->prepare($statement);
            $sth2->execute($file_id);

            my ($filename) = $sth2->fetchrow_array;
            $text .=
                "Attachment:&#160;&#160;$filename<br>\n"
              . "($c{misc}{baseurl}forms.pl?form=fid&fid=$file_id)<p>\n"
              ;
        }

        $text .= "</blockquote>\n";
        return $text;
    }
}

sub _feed_me {
    my $fname     = shift;
    my $repos_key = shift;

    my $ua = new LWP::UserAgent;
    $ua->agent( "WorkLog/Get" . $ua->agent );
    my $req = new HTTP::Request GET => $c{misc}{repos} . $repos_key;
    my $res = $ua->request($req);

    print "Content-type: " . LWP::MediaTypes::guess_media_type($fname) . "\n\n";
    print $res->content;

    return;
}

sub _get_fname {
    my $fid = shift;

    my $statement = "SELECT filename FROM files WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($fid);

    return ( $sth->fetchrow_array );
}

sub _get_key {
    my $fid = shift;

    my $statement = "SELECT repos_key FROM files WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($fid);

    return ( $sth->fetchrow_array );
}

sub _record_key {
    my $filename = shift;
    my $rpkey    = shift;

    my $statement = "INSERT INTO files (filename, repos_key) VALUES (?,?)";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $filename, $rpkey );

    return $sth->{mysql_insertid};
}

sub _db_link_file {
    my $fileid = shift;
    my $tmpid  = shift;

    my $statement = "INSERT INTO file_lut (file_id, tmp_id) VALUES (?,?)";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $fileid, $tmpid );

    return;
}

sub _absfilename {
    my $rawfile = shift;

    $rawfile =~ s/^([A-Z]\:\\.*\\)?(.+)\.?(.*)?$/$2/io;
    $rawfile =~ s/^\/.+\/(.+[^\/])$/$1/;
    return $rawfile;
}

########################################################################
######## Email routines

sub _get_didhash {
    my $tid = shift;
    my $kind = shift;

    my $statement = "SELECT dev_id FROM assignments WHERE task_id = ? AND type = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid, assign_type($kind));

    my %rhash;
    while ( my $res = $sth->fetchrow_arrayref ) {
        $rhash{ $res->[0] } = 1;
    }

    return \%rhash;
}

sub _get_list {
    my $what  = shift;
    my $from  = shift;
    my $limit = shift;

    my $statement = "SELECT $what FROM $from";
    my $sth       = $dbh->prepare($statement);
    $sth->execute();

    my $list;
    my $c = 0;
    while ( my $item = $sth->fetchrow_array ) {
        if ( $c == $limit ) {
            $list .= "\n    $item, ";
            $c = 0;
        }
        else {
            $list .= "$item, ";
        }
        $c++;
    }
    chop $list;
    chop $list;

    return $list;
}

sub _get_email {
    my $devid = shift;

    my $statement = "SELECT email FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($devid);

    return $sth->fetchrow_arrayref;
}

sub _get_devid_name {
    my $name = shift;

    my $statement = "SELECT id FROM user WHERE username = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($name);

    return ( $sth->fetchrow_array );
}

sub _get_devid_email {
    my $email = shift;

    my $statement = "SELECT id FROM user WHERE email = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($email);

    return ( $sth->fetchrow_array );
}

sub _get_devname {
    my $devid = shift;

    my $statement = "SELECT username FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($devid);

    return ( $sth->fetchrow_array );
}

sub _get_default {
    my $from = shift;
    my $what = shift;

    my $statement = "SELECT $from FROM $what where `default`='y'";
    my $sth       = $dbh->prepare($statement);
    $sth->execute();

    return ( $sth->fetchrow_array );
}

sub _mail_single {
    my $tid        = shift;
    my $ra_address = shift;
    my $subject    = shift;
    my $message    = shift;
    my $devid      = shift;

    return ( $tid, _get_email($devid), $subject, $message );
}

sub _mailformat_newtask {
    my $kind  = shift;
    my $devid = shift;

    my $subject    = "$kind: New Task Form";
    my $developers = _get_list( 'username', 'user ORDER BY username', 7 );
    my $categories = _get_list( 'name', 'categories', 6 );
    my $statuses   = _get_list( 'status', 'status ORDER BY id', 7 );
    my $priorities = _get_list( 'priority', 'priority ORDER BY id', 7 );
    my $defaultdev = _get_devname($devid);
    my $defaultcat  = _get_default( 'name',     'categories' );
    my $defaultstat = _get_default( 'status',   'status' );
    my $defaultprio = _get_default( 'priority', 'priority' );

    my $message =
            "$c{email}{header_task}                           NEW WORKLOG TASK\n"
          . "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n"
          . "  Available Developers:\n"
          . "    $developers\n"
          . "\n"
          . "  Available Categories:\n"
          . "    $categories\n"
          . "\n"
          . "  Available Statuses:\n"
          . "    $statuses\n"
          . "\n"
          . "  Available Priorities:\n"
          . "    $priorities\n"
          . "\n"
          . "\n"
          . "  Please update the form below by replying DIRECTLY BENEATH each\n"
          . "  respective line with the appropriate information (whitespace is\n"
          . "  auto-trimmed).\n"
          . "\n"
          . "  (* Indicates required)\n"
          . "  -------------------------------------------------------------------\n"
          . "            TASK : <*title of task>\n"
          . "     ASSIGNED BY : <assigned by who, default: $defaultdev>\n"
          . "     ASSIGNED TO : <assigned to who (comma sep), default: $defaultdev>\n"
          . "       COPIES TO : <copy this task to who, no default>\n"
          . "        CATEGORY : <category, default: $defaultcat>\n"
          . "          STATUS : <status, default: $defaultstat>\n"
          . "        PRIORITY : <priority, default: $defaultprio>\n"
          . "\n"
          . "\n"
          . "   DESCRIPTION:\n"
          . "        <*precise description of the task>\n"
          ;

    $message .=
            "\n"
          . "\n"
          . "   ESTIMATED DEVELOPMENT TIME\n"
          . "       EST TIME : <hours, default: 0>\n"
          . "\n"
          . "   ESTIMATED COMPLETION DATE\n"
          . "     OPTIMISTIC : <yyyy-mm-dd format, default: 0000-00-00>\n"
          . "      REALISTIC : <yyyy-mm-dd format, default: 0000-00-00>\n"
          . "       ABSOLUTE : <yyyy-mm-dd format, default: 0000-00-00>\n"
          . "\n"
          . "-----------------------------------------------------------------------\n"
          . "\n"
          . "$c{email}{footer_task}\n"
          ;

    return ( 'NULL', _get_email($devid), $subject, $message );
}

sub _mailformat_task {
    my $kind = shift;
    my $tid  = shift;

    my $statement =
      "SELECT creator, tasks.supervisor, own.email, title, description, "
      . "DATE_FORMAT(creation_date, '%a, %d %b %Y, %H:%i'), "
      . "version, st.status, priority, cat.name FROM tasks, "
      . "user own, status st, categories cat WHERE tasks.id = ? "
      . "AND owner = own.id AND tasks.status = st.id AND cat_id = cat.id";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);
    my (
        $creator, $grpldr,  $owner_email, $title,
        $descrip, $crdate,    $version, $status,      $prio,
        $catname, 
      )
      = $sth->fetchrow_array;

    my $dformat = HTML::FormatText->new( leftmargin => 0, rightmargin => 69 );
    $descrip = $dformat->format(
        HTML::TreeBuilder->new->parse("<html><body>$descrip</body></html>") );
    $title = wrap( "", "\t\t", $title );
    my $tdevs = join( ', ', _personlist( $tid, 'developer' ));
    my $tobs  = join( ', ', _personlist( $tid, 'observers' ));
    my $grpldr_str = _uid2username($grpldr);
    my $whodoneit  = _uid2username(_get_current_id);
    my $developers = wrap( "", "\t\t", $tdevs );
    my $observers  = wrap( "", "\t\t", $tobs );
    my $subject    = "$kind (by $whodoneit): $title ($tid)";

    my $message =
            "$c{email}{header_task}                              WORKLOG TASK\n"
          . "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n"
          . "TASK...........: $title\n"
          . "CREATION DATE..: $crdate\n"
          . "SUPERVISOR.....: $grpldr_str\n"
          . "ASSIGNED TO....: $developers\n"
          . "COPIES TO......: $observers\n"
          . "CATEGORY.......: $catname\n"
          . "TASK ID........: $tid ($c{misc}{httphost}$c{misc}{baseurl}?tid=$tid)\n"
          . "VERSION........: $version\n"
          . "STATUS.........: $status\n"
          . "PRIORITY.......: $prio\n"
          . "\n"
          . "DESCRIPTION:\n"
          . "\n"
          . "$descrip\n"
          . "\n"
          . "PROGRESS NOTES:\n"
          . "\n"
          ;

    $statement = "SELECT count(*) FROM amendments WHERE task_id = ? AND type = 'note'";
    $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    my $count = ( $sth->fetchrow_array );

    $statement = "SELECT id, dev_id, date_format(date, '%a, %d %b %Y, %H:%i'), text FROM amendments WHERE task_id = ? AND type = 'note' ORDER BY date DESC LIMIT 10";
    $sth = $dbh->prepare($statement);
    $sth->execute($tid);
    my $c = 0;
    while ( my ( $amend_id, $devid, $date, $text ) = $sth->fetchrow_array ) {
        my $devname = _get_devname($devid);
        $devname = 'Unknown' if ( $devname eq '' );
        my $pformat = HTML::FormatText->new( leftmargin => 0, rightmargin => 69 );
        $text = ( $text !~ m/^\<p\>.*$/ ) ? "<p>$text" : $text;
        $text = $pformat->format( HTML::TreeBuilder->new->parse("<html><body>$text</body></html>") );
        $text .= "\n";
        $message .= "-=-=($devname - $date)=-=-\n$text";
        $c++;
    }

    if ( $count > 10 ) {
        $message .= "\t" . '-' x 60 . "\n\n";
        $message .= "\t\t-=-=(View All Progress Notes, $count total)=-=-\n";
        $message .= "\t$c{misc}{httphost}$c{misc}{baseurl}index.pl?tid=$tid&nolimit=1\n";
    }

    $message .=
            "\n"
          . "\n"
          . "ESTIMATED WORK TIME\n"
          . "\n"
          . "ESTIMATED COMPLETION DATE\n"
          . "-----------------------------------------------------------------------\n"
          . "$c{email}{footer_task}\n"
          ;

    my @l_email;
    push @l_email, $owner_email;
    push @l_email, _personlist_email( $tid, "developer" );
    push @l_email, _personlist_email( $tid, "observers" );
    push @l_email, _get_grpldr_email( _get_grpldrid($tid) );

    return ( $tid, _remove_dups( \@l_email ), $subject, $message );
}

sub _textformat_task {
    my $tid = shift;

    my $statement =
      "SELECT creator, supervisor, designer, designrev, developer, coderev1, coderev2, qa, "
      . "title, description, "
      . "DATE_FORMAT(creation_date, '%a, %d %b %Y, %H:%i'), "
      . "version, st.status, priority, cat.name FROM tasks, "
      . "status st, categories cat WHERE tasks.id = ? "
      . "AND tasks.status = st.id AND cat_id = cat.id";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);
    my (
        $creator, $supervisor, $lead_arch, $arch_rev, $implementor, $coderev1, $coderev2, $qa,
        $title, $descrip,
        $crdate,
        $version, $status, $prio, $catname,
      )
      = $sth->fetchrow_array;

    my $dformat = HTML::FormatText->new( leftmargin => 0, rightmargin => 69 );
    $descrip = $dformat->format(
        HTML::TreeBuilder->new->parse("<html><body>$descrip</body></html>") );
    $title = wrap( "", "\t\t", $title );
    $creator    = _uid2username($creator);
    $supervisor = _uid2username($supervisor);
    $lead_arch  = _uid2username($lead_arch);
    $arch_rev   = _uid2username($arch_rev);
    $implementor = _uid2username($implementor);
    $coderev1   = _uid2username($coderev1);
    $coderev2   = _uid2username($coderev2);
    $qa         = _uid2username($qa);
    my $observers  = join( ', ', _personlist($tid, 'observers'));
    my $subject    = "$title ($tid)";

    my $depparent  = '';
    foreach ( _depends_text( $tid, 'parent' ) ) {
        $depparent .= wrap( ' 'x17, ' 'x22, $_ );
    }
    my $depchild   = '';
    foreach ( _depends_text( $tid, 'child' ) ) {
        $depchild  .= wrap( ' 'x17, ' 'x22, $_ );
    }

    my $message =
            "$c{email}{header_task}                              WORKLOG TASK\n"
          . "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n"
          . "TASK...........: $title\n"
          . "CREATION DATE..: $crdate\n"
          . "CREATED BY.....: $creator\n"
          . "SUPERVISOR.....: $supervisor\n"
          . "LEAD ARCHITECT.: $lead_arch\n"
          . "ARCH REVIEW....: $arch_rev\n"
          . "IMPLEMENTOR....: $implementor\n"
          . "1st CODE REVIEW: $coderev1\n"
          . "2nd CODE REVIEW: $coderev2\n"
          . "QA.............: $qa\n"
          . "COPIES TO......: $observers\n"
          . "CATEGORY.......: $catname\n"
          . "TASK ID........: $tid ($c{misc}{httphost}$c{misc}{baseurl}?tid=$tid)\n"
          . "VERSION........: $version\n"
          . "STATUS.........: $status\n"
          . "PRIORITY.......: $prio\n"
          . "\n"
          . "DEPENDS ON.....:\n$depchild\n"
          . "DEPENDANT......:\n$depparent\n"
          . "DESCRIPTION:\n"
          . "\n"
          . "$descrip\n"
          . "\n"
          . "PROGRESS NOTES:\n"
          . "\n"
          ;

    $statement = "SELECT count(*) FROM amendments WHERE task_id = ? AND type = 'note'";
    $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    my $count = ( $sth->fetchrow_array );

    $statement = "SELECT id, dev_id, date_format(date, '%a, %d %b %Y, %H:%i'), text FROM amendments WHERE task_id = ? AND type = 'note' ORDER BY date DESC LIMIT 10";
    $sth = $dbh->prepare($statement);
    $sth->execute($tid);
    my $c = 0;
    while ( my ( $amend_id, $devid, $date, $text ) = $sth->fetchrow_array ) {
        my $devname = _get_devname($devid);
        $devname = 'Unknown' if ( $devname eq '' );
        my $pformat = HTML::FormatText->new( leftmargin => 0, rightmargin => 69 );
        $text = ( $text !~ m/^\<p\>.*$/ ) ? "<p>$text" : $text;
        $text = $pformat->format(
            HTML::TreeBuilder->new->parse("<html><body>$text</body></html>") );
        $text .= "\n";
        $message .= "-=-=($devname - $date)=-=-\n$text";
        $c++;
    }

    if ( $count > 10 ) {
        $message .= "\t" . '-' x 60 . "\n\n";
        $message .= "\t\t-=-=(View All Progress Notes -> $count total)=-=-\n";
        $message .= "\t$c{misc}{httphost}$c{misc}{baseurl}index.pl?tid=$tid&nolimit=1\n";
    }

    $message .=
            "\n"
          . "\n"
          . "-----------------------------------------------------------------------\n"
          . "$c{email}{footer_task}\n"
          ;

    return ($message);
}

sub _mailformat_reqtok {
    my @email   = shift;
    my $chaltok = shift;
    my $kind    = 'Requested';

    my $subject = "$kind: Change Password Token";
    my $message =
            "Someone (possibly you) has requested to change your WorkLog password. If you would like to complete this process, please take this Authorization Token (13 characters):\n"
          . "\n"
          . "  $chaltok\n"
          . "\n"
          . "And go to the URL below to change (or sign-up for a new) password.\n"
          . "\n"
          . "  ${url}?form=chpass\n"
          . "\n"
          . "Have a nice day.\n"
          . "\n"
          . "\n"
          . "WorkLog (v$c{misc}{version})\n"
          ;

    $message = wrap( "", "", $message );

    return ( 'NULL', \@email, $subject, $message );
}

sub _mail_developer {
    my $tid        = shift;
    my $ra_address = shift;
    my $subject    = shift;
    my $message    = shift;

    foreach my $address (@$ra_address) {
        my $date = POSIX::strftime( "%a, %e %b %Y %X %z (%Z)", localtime );
        my $mesg_id      = _message_id("worklog.$c{email}{cdomain}");
        my $mail_message =
            "Message-Id: $mesg_id\n"
          . "From: $c{email}{from}\n"
          . "To: $address\n"
          . "Subject: $subject\n"
          . "Date: $date\n"
          . "\n"
          . "$message\n"
          . "\n"
          ;

        _stor_mesg_id( _parse_id_key($mesg_id), $tid, _get_devid_email($address) );

        my $smtp = Net::SMTP->new(
            $c{email}{smtp},
            Hello   => $c{email}{domain},
            Timeout => 60,
            Debug   => 0,
        );

        $smtp->mail("$c{email}{from}")
          or die "Failed to specify a sender [$c{email}{from}]";
        $smtp->to( $address, $c{misc}{dbemail} )
          or die "Failed to specify a recipient [$address]";
        $smtp->data( [$mail_message] ) or die "Failed to send a message";
    }

    return;
}

sub _notify_cat_owner {
    my $tid    = shift;
    my $cat_id = shift;

    my $cat_owner_id = _get_cat_owner_id($cat_id);

    _mail_developer( _mail_single( _mailformat_task( 'Newly Added', $tid ), $cat_owner_id ) )
      unless $cat_owner_id eq '';

    return;
}

sub _stor_mesg_id {
    my $mesg_id = shift;
    my $tid     = shift;
    my $devid   = shift;

    my $statement = "INSERT INTO mesg_id_lut (mesg_id, task_id, dev_id) VALUES (?,?,?)";
    my $sth = $dbh->prepare($statement);
    $sth->execute( $mesg_id, $tid, $devid );

    return;
}

sub _parse_id_key {
    my $mid = shift;
    $mid =~ s/<([\.0-9a-zA-Z]+)\@.+>/$1/;
    return $mid;
}

########################################################################
######## Inserting routines

sub _wk_insert_pnote {
    my $tid   = shift;
    my $devid = shift;
    my $text  = shift;
    my $upid  = shift;

    my $statement = "SELECT id FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);
    _error( $c{err}{noid}, $statement ) unless $sth->fetch;

    $statement = "INSERT INTO amendments (task_id, dev_id, date, text, type) VALUES (?, ?, now(), ?, 'note')";
    $sth = $dbh->prepare($statement);
    $sth->execute( $tid, $devid, _htmlify_text($text) );

    my $amend_id = $sth->{mysql_insertid};
    $statement = "UPDATE file_lut SET amend_id = ? WHERE tmp_id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute( $amend_id, $upid );

    return;
}

sub _wk_insert_progrep {
    my $tid   = shift;
    my $devid = shift;
    my $text  = shift;

    my $statement = "SELECT id FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);
    _error( $c{err}{noid}, $dbh->errstr ) unless $sth->fetch;

    $statement = "INSERT INTO amendments (task_id, dev_id, date, text, type) VALUES (?, ?, now(), ?, 'note')";
    $sth = $dbh->prepare($statement);
    $sth->execute( $tid, $devid, _htmlify_text($text) );

    return;
}

########################################################################
######## Converting routines

sub _conv_prio {
    chomp( my $tprio = shift );

    $tprio = lc $tprio;
    print "Prio: $tprio\n";
    print "Conv: $c{misc}{prio_conv}{$tprio}\n";

    return $c{misc}{prio_conv}{$tprio};
}

sub _conv_status {
    chomp( my $stat = shift );

    $stat = lc $stat;

    my $statement = "SELECT status, id FROM status";
    my $sth       = $dbh->prepare($statement);
    $sth->execute();

    while ( my $hr = $sth->fetchrow_hashref ) {
        if ( $stat eq lc $hr->{status} ) {
            print "Status: $stat\n";
            $stat = $hr->{id};
            last;
        }
    }

    print "Conv: $stat\n";
    return $stat;
}

sub _conv_catid {
    chomp( my $category = shift );

    $category = lc $category;

    my $statement = "SELECT name, id FROM categories";
    my $sth       = $dbh->prepare($statement);
    $sth->execute();

    while ( my $hr = $sth->fetchrow_hashref ) {
        if ( $category eq lc $hr->{name} ) {
            print "Category: $category\n";
            $category = $hr->{id};
            last;
        }
    }

    print "Conv: $category\n";
    return $category;
}

########################################################################
######## Updating routines

sub _wk_update_null {
    my $tid = shift;
    my $upd = shift;

    return;
}

sub _wk_update_pnote {
    my $tid = shift;
    my $upd = shift;
    my $did = shift;

    _wk_insert_pnote( $tid, $did, $upd, '' );

    return;
}

sub _wk_update_assby {
    my $tid   = shift;
    my $name  = shift;
    my $devid = shift;

    my @names = split /,/, $name;

    my $statement = "UPDATE tasks SET owner = ?, enteredby = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( _get_devid_name( _trim_ws( $names[0] ) ), $devid, $tid );

    return;
}

sub _wk_update_assto {
    my $tid   = shift;
    my $names = shift;

    my $statement = "DELETE FROM assignments WHERE task_id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    foreach my $developer ( split /,/, $names ) {
        $statement = "INSERT INTO assignments (task_id, dev_id) VALUES (?, ?)";
        $sth       = $dbh->prepare($statement);
        $sth->execute( $tid, _get_devid_name( _trim_ws($developer) ) );
    }

    return;
}

sub _wk_update_grpldr {
    my $tid    = shift;
    my $grpldr = shift;

    my $old_grpldr = _get_taskgrpldr_name($tid);

    my $statement = "UPDATE tasks SET supervisor = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $grpldr, $tid );

    $old_grpldr .= "\n";
    $grpldr = _get_taskgrpldr_name($tid) . "\n";

    _mk_diff_log( $tid, _get_current_id(), 'Supervisor updated.', $old_grpldr, $grpldr );

    return;
}

sub _wk_update_version {
    my $tid     = shift;
    my $version = shift;

    my $old_version = _get_txt_version($tid);

    my $statement = "UPDATE tasks SET version = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $version, $tid );

    $old_version .= "\n";
    $version .= "\n";

    _mk_diff_log( $tid, _get_current_id(), 'Version updated.', $old_version, $version );

    return;
}

sub _wk_update_status {
    my $tid    = shift;
    my $status = shift;

    my $old_status = _get_txt_status($tid);

    my $statement = "SELECT id FROM status WHERE status = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($status);
    my $res = $sth->fetchrow_arrayref;

    $statement = "UPDATE tasks SET status = ? WHERE id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute( $res->[0], $tid );

    $old_status .= "\n";
    $status .= "\n";

    _mk_diff_log( $tid, _get_current_id(), 'Status updated.', $old_status, $status );

    return;
}

sub _wk_update_cate {
    my $tid  = shift;
    my $cate = shift;

    my $old_cate = _get_txt_category($tid);

    my $statement = "SELECT id FROM categories WHERE name = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($cate);
    my $res = $sth->fetchrow_arrayref;

    $statement = "UPDATE tasks SET cat_id = ? WHERE id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute( $res->[0], $tid );

    $old_cate .= "\n";
    $cate .= "\n";

    _mk_diff_log( $tid, _get_current_id(), 'Category updated.', $old_cate, $cate );

    return;
}

sub _wk_update_dates {
    my $tid = shift;
    chomp( my $dopti = shift );
    chomp( my $dreal = shift );
    chomp( my $dabso = shift );

    my $old_dates = _get_txt_dates($tid);
    my $new_dates =
            "OPTI: $dopti\n"
          . "REAL: $dreal\n"
          . "ABSO: $dabso\n"
          ;

    my $statement = "UPDATE tasks SET doc_opti = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $dopti, $tid );

    $statement = "UPDATE tasks SET doc_real = ? WHERE id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute( $dreal, $tid );

    $statement = "UPDATE tasks SET doc_abso = ? WHERE id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute( $dabso, $tid );

    _mk_diff_log( $tid, _get_current_id, 'Date estimates updated.', $old_dates, $new_dates );

    return;
}

sub _wk_update_time {
    my $tid = shift;
    chomp( my $time = shift );

    my $old_time = _get_time($tid);

    my $statement = "UPDATE tasks SET devtime = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $time, $tid );

    $old_time .= "\n";
    $time .= "\n";

    _mk_diff_log( $tid, _get_current_id, 'Hours estimate updated.', $old_time, $time );

    return;
}

sub _wk_update_prio {
    my $tid = shift;
    chomp( my $prio = shift );

    my $old_prio = _get_prio($tid);

    my $statement = "UPDATE tasks SET priority = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $prio, $tid );

    $old_prio .= "\n";
    $prio .= "\n";

    _mk_diff_log( $tid, _get_current_id, 'Priority updated.', $old_prio, $prio );

    return;
}

sub _wk_update_devtime {
    my $tid = shift;
    chomp( my $devtime = shift );

    my $statement = "UPDATE tasks SET devtime = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $devtime, $tid );

    return;
}

sub _wk_update_dopti {
    my $tid = shift;
    chomp( my $dopti = shift );

    my $statement = "UPDATE tasks SET doc_opti = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $dopti, $tid );

    return;
}

sub _wk_update_dreal {
    my $tid = shift;
    chomp( my $dreal = shift );

    my $statement = "UPDATE tasks SET doc_real = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $dreal, $tid );

    return;
}

sub _wk_update_dabso {
    my $tid = shift;
    chomp( my $dabso = shift );

    my $statement = "UPDATE tasks SET doc_abso = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $dabso, $tid );

    return;
}

sub _wk_update_descrip {
    my $tid     = shift;
    my $descrip = shift;

    my $old_descrip = _get_descrip($tid);

    $old_descrip =~ s/^<pre>//g;
    $old_descrip =~ s/<\/pre>$//g;

    my $statement = "UPDATE tasks SET description = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( _htmlify_text( _sanitize_txt_input($descrip) ), $tid );

    $descrip .= "\n";
    $old_descrip .= "\n";

    _mk_diff_log(
        $tid,                    _get_current_id,
        'High Level Description modified.', $old_descrip,
        $descrip
    );

    return;
}

sub _wk_update_hla {
    my $tid     = shift;
    my $hla = shift;

    my $old_hla = _get_hla($tid);

    $old_hla =~ s/^<pre>//g;
    $old_hla =~ s/<\/pre>$//g;

    my $statement = "UPDATE tasks SET hilevelarch = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( _htmlify_text( _sanitize_txt_input($hla) ), $tid );

    $hla .= "\n";
    $old_hla .= "\n";

    _mk_diff_log(
        $tid,                    _get_current_id,
        'High-Level Specification modified.', $old_hla,
        $hla
    );

    return;
}

sub _wk_update_lld {
    my $tid     = shift;
    my $lld = shift;

    my $old_lld = _get_lld($tid);

    $old_lld =~ s/^<pre>//g;
    $old_lld =~ s/<\/pre>$//g;

    my $statement = "UPDATE tasks SET loleveldesign = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( _htmlify_text( _sanitize_txt_input($lld) ), $tid );

    $lld .= "\n";
    $old_lld .= "\n";

    _mk_diff_log(
        $tid,                    _get_current_id,
        'Low Level Design modified.', $old_lld,
        $lld
    );

    return;
}

sub _wk_update_title {
    my $tid   = shift;
    my $title = shift;

    #  $title =~ s/\"/&quot;/g;
    #  $title =~ s/</&lt;/g;

    my $old_title = _get_title $tid;

    my $statement = "UPDATE tasks SET title = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $title, $tid );

    $old_title .= "\n";
    $title .= "\n";

    _mk_diff_log( $tid, _get_current_id, 'Title modified.', $old_title, $title );

    return;
}

sub _wk_update_category {
    my $tid = shift;
    chomp( my $cat_id = shift );

    my $old_cat_id = _get_txt_category $tid;

    my $statement = "UPDATE tasks SET cat_id = ? WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute( $cat_id, $tid );

    _mk_diff_log( $tid, _get_current_id, 'Category updated.', $old_cat_id, $cat_id );

    return;
}

sub _wk_set_updated {
    my $tid = shift;

    my $statement = "UPDATE tasks SET been_updated = '1' WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return;
}

########################################################################
######## Miscallaneous routines

sub _mk_diff_log {
    my $tid     = shift;
    my $did     = shift;
    my $comment = shift;
    my $old     = shift;
    my $new     = shift;

    $old = _htmlify_text( _sanitize_txt_input($old) );
    $new = _htmlify_text( _sanitize_txt_input($new) );

    $old =~ s/^<pre>//g;
    $old =~ s/<\/pre>$//g;
    $new =~ s/^<pre>//g;
    $new =~ s/<\/pre>$//g;

    my $oldfile = "/tmp/wklog.$tid.old.$$";
    my $newfile = "/tmp/wklog.$tid.new.$$";
    open( OLD, ">$oldfile" );
    open( NEW, ">$newfile" );
    print OLD $old;
    print NEW $new;

    my $diff = `diff -ub $oldfile $newfile`;
    $diff = ( $diff eq '' ) ? "No change." : $diff;

    unlink($oldfile);
    unlink($newfile);

    my $compost_diff = "$comment\n$diff";

    _wk_insert_progrep( $tid, $did, $compost_diff );

    return;
}

sub _is_arch_ready {
    my $tid = shift;

    my $statement =
      "SELECT stat.status FROM tasks t, status stat WHERE t.id = ? "
      . "AND t.status = stat.id";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array eq 'Complete' ) ? 1 : 0;
}

sub _get_descrip {
    my $tid = shift;

    my $statement = "SELECT description FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_hla {
    my $tid = shift;

    my $statement = "SELECT hilevelarch FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_lld {
    my $tid = shift;

    my $statement = "SELECT loleveldesign FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_title {
    my $tid = shift;

    my $statement = "SELECT title FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_prio {
    my $tid = shift;

    my $statement = "SELECT priority FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_ownerid {
    my $tid = shift;

    my $statement = "SELECT owner FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_cat_owner_id {
    my $cat_id = shift;

    my $statement = "SELECT cat_owner FROM categories WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($cat_id);

    return ( $sth->fetchrow_array );
}

sub _get_grpldrid {
    my $tid = shift;

    my $statement = "SELECT supervisor FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_grpldr_email {
    my $grpldr_id = shift;

    my $statement = "SELECT email FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($grpldr_id);

    return ( $sth->fetchrow_array );
}

sub _get_taskowner_name {
    my $tid = shift;

    my $statement = "SELECT username FROM user, tasks WHERE user.id = owner AND tasks.id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_taskgrpldr_name {
    my $tid = shift;

    my $statement = "SELECT username FROM user, tasks WHERE user.id = tasks.supervisor AND tasks.id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_owner_name {
    my $id = shift;

    my $statement = "SELECT username FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($id);

    return ( $sth->fetchrow_array );
}

sub _get_grpldr_name {
    my $id = shift;

    my $statement = "SELECT username FROM user WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($id);

    return ( $sth->fetchrow_array );
}

sub _get_txt_category {
    my $tid = shift;

    my $statement = "SELECT name FROM categories c, tasks t WHERE t.cat_id=c.id AND t.id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_txt_version {
    my $tid = shift;

    my $statement = "SELECT version FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_txt_status {
    my $tid = shift;

    my $statement = "SELECT s.status FROM status s, tasks t WHERE t.status=s.id AND t.id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_status {
    my $id = shift;

    my $statement = "SELECT status FROM status WHERE id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($id);

    return ( $sth->fetchrow_array );
}

sub _get_txt_dates {
    my $tid = shift;

    my $statement = "SELECT doc_opti, doc_real, doc_abso FROM tasks WHERE id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    my ( $dopti, $dreal, $dabso ) = $sth->fetchrow_array;

    my $txt =
            "OPTI: $dopti\n"
          . "REAL: $dreal\n"
          . "ABSO: $dabso\n"
          ;

    return ($txt);
}

sub _get_time {
    my $tid = shift;

    my $statement = "SELECT devtime FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _get_catname {
    my $tid = shift;

    my $statement = "SELECT name FROM categories cat, tasks t WHERE t.cat_id=cat.id AND t.id= ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid);

    return ( $sth->fetchrow_array );
}

sub _sanitize_txt_input {
    my $txt = shift;

    $txt =~ s/\"/&quot;/g;
    $txt =~ s/</&lt;/g;

    return $txt;
}

sub _nth {
    local ($_) = @_;
    return "${_}st" if /1$/;
    return "${_}nd" if /2$/;
    return "${_}rd" if /3$/;
    return "${_}th";
}

# This appears to be redefined further below
#
#sub _hyperlink {
#    my $what = shift;
#    my $link = shift;
#
#    return "<a href=\"$link\">$what</a>";
#}

sub _debug {
    my $mesg = shift;
    print $mesg if ( $c{misc}{DEBUG} );
    return;
}

sub _trim_ws {
    my $text = shift;

    $text =~ s/\n/ /g;
    $text =~ s/^\s*(.+)$/$1/;
    $text = reverse $text;
    $text =~ s/^\s*(.+)$/$1/;
    $text = reverse $text;

    $text =~ s/^\s*$//;

    return $text;
}

sub _htmlify_text {
    my $text = shift;

    # disable all incoming HTML tags
    $text =~ s/\</\&lt\;/g;
    $text =~ s/\>/\&gt\;/g;

    # htmlify it
    $text = "<pre>$text</pre>";    #$t2h->text2html($text);

    return $text;
}

# hyperlink: Generate HTML link 
sub _hyperlink {
    $_ = shift;

    #s/&/&amp;/g; 
    #s/</&lt;/g; 
    my $new;
    while (m/=\?iso-8859-1\?Q\?([^\?]*)\?=/) {
        $new = $1;
        $new =~ s/=(\w\w)/"&#".hex($1).";"/gie;    # Convert quoted-printable
        s/=\?iso-8859-1\?Q\?[^\?]*\?=/$new/;
    }
s&(ftp|gopher|http|https)(://[^<>),"\&\s]*[^<>),."\&\s])&<A HREF="$1$2">$1$2</A>&g;
    s&(mailto|news|telnet)(:[^<>)\],"\s]+)&<A HREF="$1$2">$1$2</A>&g;
    s&(^|\s)(ftp|gopher)(\.[\w./-]+)(\s|$)&$1<A HREF="$2://$2$3/">$2$3</A>$4&g;
    s&(^|\s)(www\.[\w./-]+)(\s|$)&$1<A HREF=" http://$2/">$2</A>$3&g;
s&(article|In-Reply-To:|Message-ID:|References:)(\s+\&lt;)([^@>"\s]+@[^>"\s]*)&$1$2<A HREF="$3">$3</A>&gi;
s/(^|^"|[^=]"|SMTP:|[()\[\]\s]|(&lt;)+)([^&()>":\[\]\s]+@)([\w\-.]+\.[\w\-]+|\[\d+\.\d+\.\d+\.\d+\])/$1<A HREF=" mailto:$3$4">$3$4<\/A>/g;
    return $_;
}

sub _field_hidden {
    my ($field) = @_;
    my $hiddenfields = "|" . join( "|", qw{
        priority
        version
        copies
        codereview
        status
        groupldr
        assigned
    } ) . "|";
    return $hiddenfields =~ /\|$field\|/;
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

WorkLog - Developement Progress Tool 

=head1 SYNOPSIS

  use WorkLog;

=head1 DESCRIPTION

Worklog allows you to track the work you do in various projects and
tasks within them. You define projects and tasks, and then file progress
reports on tasks as you go along. Monitors time remaining on tasks and
projects.

=head2 EXPORT

None by default.



=head1 SEE ALSO

I should really write something here.

=head1 AUTHOR

Andrew Sweger, E<lt>yDNA@perlocity.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Andrew Sweger and Addnorya
Copyright (C) 2003 by Matt Wagner and MySQL AB

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.


=cut

