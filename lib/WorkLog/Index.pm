#
# WorkLog/Index.pm
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

package WorkLog::Index;
use warnings;
no warnings 'uninitialized';
use strict;

our $VERSION = sprintf "%d.%03d", q$Revision: 1.25 $ =~ /(\d+)/g;

use WorkLog::Database;
use WorkLog::CGI;
use WorkLog qw(
    all_children_of
    creator_html
    error
    field_hidden
    field_hidden
    get_catname
    get_current_id
    get_devname
    get_status
    get_taskgrpldr_name
    get_title
    grandchildren_of
    has_seen
    html_role_assignment
    hyperlink
    is_arch_ready
    mark_seen
    mk_button
    mk_title
    pad_me
    page_end
    page_start
    percentages
    personlist
    priority_color
    table_start
    textformat_task
    updatetime_html
);

# Exporter
    require Exporter;
    use vars qw(%EXPORT_TAGS @ISA @EXPORT_OK);
    @ISA = qw(Exporter);
    use constant FUNCTIONS => qw(
         view_as_text
         view_search_results
         view_task
         view_virtual_task
         view_tasks
        _view_tasks_nocat
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

my $cgi = new WorkLog::CGI;
my $dbh = new WorkLog::Database;
my $url = $cgi->url( -absolute => 1 );

use WLCONFIG;
use vars qw(%c);
*c = \%WLCONFIG::conf;

########################################################################
######## Viewing a list of search results

sub _view_search_results {
    my $search_str = shift;
    my $cat_id     =
      ( $cgi->param("catid") ) ? "=" . $cgi->param("catid") : "like '%'";
    my $arch =
      ( $cgi->param("arch") eq 'y' || $cgi->param("arch") eq 'n' )
      ? $cgi->param("arch")
      : 'n';
    my $includeall = $cgi->param("includeall") || '';

    my $html_page = page_start("Search Results");
    $html_page .= table_start( 'minimal', { actions => 0, fund => 0, view => 'active', vflag => 'active' } );

    my $fromsel = ( $arch eq 'y' ) ? ' selected' : '';

    $html_page .=
        "<table width=\"100%\">\n"
      . "<tr><td align=center>\n"
      . "<table bgcolor=\"$c{color}{mysqlblu}\" width=\"100%\" cellpadding=0 cellspacing=1>\n"
      . "<tr><td>\n"
      . "<table bgcolor=\"$c{color}{ltblue}\" width=\"100%\" cellpadding=2>\n"
      . "<tr><td align=center>\n"
      . "<form method=get action=\"$c{misc}{baseurl}index.pl\" name=\"BigSearchWorkLog\">\n"
      . "<font size=\"+1\">Search for: <input type=text name=search size=40 value=\"$search_str\"> <input type=submit value=\" Search! \" style=\"background-color: #f0f0f0\">\n"
      . "<br><br>\n"
      . "from: <select style=\"width: 120px\" name=\"arch\">\n"
      . "<option value=\"n\">active tasks</option>\n"
      . "<option value=\"y\"$fromsel>inactive tasks</option>\n"
      . "</select>\n"
      . "within: <select style=\"width: 120px\" name=\"catid\">\n"
      . "<option value=\"\">all queues</option>\n"
      ;

    my $statement = "SELECT id, name FROM categories ORDER BY name";
    my $sth       = $dbh->prepare($statement);
    $sth->execute;

    while ( my $res = $sth->fetchrow_arrayref ) {
        my $sel = ( $res->[0] eq $cgi->param("catid") ) ? " selected" : "";
        $html_page .= "<option value=\"$res->[0]\"$sel>$res->[1]</option>\n";
    }

    my $matchsel = ( $cgi->param("matching") eq 'all' ) ? ' selected' : '';

    $html_page .=
        "</select>\n"
      . "matching: <select style=\"width: 120px\" name=\"matching\">\n"
      . "<option value=\"any\">any of the words</option>\n"
      . "<option value=\"all\"$matchsel>all of the words</option>\n"
      . "</select>\n"
      . "<br><input type=\"checkbox\" value=\"checked\" name=\"includeall\" $includeall>"
      . "Include Cancelled and Un-Assigned Tasks"
      . "</font>\n"
      . "</form>\n"
      . "</td></tr>\n"
      . "</table></td></tr></table></td></tr></table>\n"
      . "<br>\n"
      . "<font size=\"+1\">Search Results:</font>\n"
      . "<hr>\n"
      ;

    my $search_str2 = $search_str;
    $search_str2 =~ s/\s/%' OR d.username LIKE '%/g;

    # Search assigned tasks for name
    $statement =
      "SELECT t.id, t.title, c.name FROM tasks t, user d, categories c "
      . "WHERE (d.username LIKE '%$search_str2%') "
      . "AND d.id = t.developer AND cat_id $cat_id AND arch='$arch' AND c.id=t.cat_id "
      . ($includeall eq 'checked' ? 'AND status <> 5 AND status <> 9 ' : '')
      . "ORDER BY t.creation_date DESC";
    $sth = $dbh->prepare($statement);
    $sth->execute;

    my $results = 0;
    $html_page .= "<table width=\"100%\" border=0 cellpadding=0 cellspacing=2><tr><td></td><td align=right><b><em><font size=\"-1\">ID</font></em></b></td><td></td><td align=left><b><em><font size=\"-1\">Task</font></em></b></td></tr>\n";
    my %tid_tracker;
    while ( my ( $task_id, $task_title, $cname ) = $sth->fetchrow_array ) {
        next if ( $tid_tracker{$task_id} );
        $tid_tracker{$task_id} = 1;
        $results = 1;
        $html_page .= "<tr><td width=15 align=right><img src=\"images/box.png\"></td><td align=right>$task_id</td><td>&#160;--</td><td><a href=\"index.pl?tid=$task_id\">$task_title</a> <font size=\"-1\">[$cname]</font></td></tr>\n";
    }

    if ( $cgi->param("matching") eq 'all' ) {
        $search_str =~ s/\s/ +/g;
    }

    # Search task titles, descriptions, and progress reports
    $statement =
      "(SELECT DISTINCT t.id, t.title, c.name, "
      . "MATCH(t.title,t.description) AGAINST (" . $dbh->quote($search_str) . ") as score "
      . "FROM tasks t, categories c "
      . "WHERE MATCH(t.title,t.description) AGAINST (" . $dbh->quote($search_str) . " IN BOOLEAN MODE) "
      . "AND cat_id $cat_id AND arch='$arch' AND c.id=t.cat_id "
      . ($includeall eq 'checked' ? 'AND status <> 5 AND status <> 9) ' : ') ')
      . "UNION "
      . "(SELECT DISTINCT t.id, t.title, c.name, "
      . "MATCH(a.text) AGAINST (" . $dbh->quote($search_str) . ") as score "
      . "FROM tasks t, categories c, amendments a "
      . "WHERE a.task_id=t.id AND MATCH(a.text) AGAINST (" . $dbh->quote($search_str) . " IN BOOLEAN MODE) "
      . "AND cat_id $cat_id AND arch='$arch' AND c.id=t.cat_id) "
      . "ORDER BY score DESC";
    $sth = $dbh->prepare($statement);
    $sth->execute;

    while ( my ( $task_id, $task_title, $cname, $score ) =
        $sth->fetchrow_array )
    {
        next if ( $tid_tracker{$task_id} );
        $tid_tracker{$task_id} = 1;
        $results = 1;
        $html_page .= "<tr><td width=15 align=right><img src=\"images/box.png\"></td><td align=right>$task_id</td><td>&#160;--</td><td><a href=\"index.pl?tid=$task_id\">$task_title</a> <font size=\"-1\">[$cname]</font><!-- ($score) --></td></tr>\n";
    }

    $html_page .= ( !$results ) 
      ? "<tr><ul><li>No results found.</ul></td></tr></table>\n"
      : "</table>\n";

    $html_page .= page_end('tasks');

    print $html_page;
}

########################################################################
######## Viewing a list of tasks

sub _view_tasks {
    my $view = ( $cgi->param('archtask') ) ? 'archived' : 'active';
    my $vflag = ( $view eq 'active' ) ? 'n' : 'y';
    my $show_devid = $cgi->param('show_devid') || 0;
    my $catname    = shift || "";
    my $html_page;

    if ( $catname eq '' ) {
        print _view_tasks_nocat($view);
        return;
    }

    $html_page = page_start("$catname");
    $html_page .= table_start( 'normal', { actions => 1, fund => 1, view => $view, vflag => $view } );

    $catname = ( $catname =~ m/^MASTER\-(.+)$/ ) ? "%-$1" : $catname;
    my $master = ( $cgi->param('catname') =~ m/^MASTER\-(.+)$/ ) ? 1 : 0;

    my $statement =
      "SELECT id, name FROM categories WHERE name LIKE ? ORDER BY name";
    my $sth = $dbh->prepare($statement);
    $sth->execute($catname);

    $html_page .= "<table width=\"100%\" cellpadding=2 cellspacing=0 border=0>\n";

    while ( my ( $cat_id, $cat_name ) = $sth->fetchrow_array ) {
        my $order_by;
        my $param_desc = defined $cgi->param('desc') ? $cgi->param('desc') : '1';
           $param_desc = $param_desc > 0 ? '1' : '0';
        my $sort_flag = ( $param_desc ) ? '1' : '0';
        my $sort_direction = ($sort_flag) ? 'ASC' : 'DESC';
        my $mylim = ( ($cgi->param('lim') || '') eq 'all' ) ? 'lim=all&' : '';
        my $shwdvd =
          ( $show_devid == 0 ) 
          ? "$mylim"
          : "${mylim}show_devid=$show_devid&";
        my $sort_by = $cgi->param('sort') || '';
        my $rib = $cat_name =~ /-RawIdeaBin$/ || 0;

        my %heading = (
            'prio'    => "<a href=\"?${shwdvd}sort=prio\">Priority</a>",
            'grpldr'  => "<a href=\"?${shwdvd}sort=grpldr\">Supervisor</a>",
            'assign'  => "<a href=\"?${shwdvd}sort=assign\">Assigned</a>",
            'status'  => "<a href=\"?${shwdvd}sort=status\">Status</a>",
            'version' => "<a href=\"?${shwdvd}sort=version\">Version</a>",
            'title'   => "<a href=\"?${shwdvd}sort=title\">Task</a>",
            'tid'     => "<a href=\"?${shwdvd}sort=tid\">ID</a>",
            'queue'   => 'Queue',
        );

        if ( $sort_by eq '' && $cat_name =~ m/-Sprint$/ ) {
            $order_by = "dev.username $sort_direction, t.priority DESC, t.title";
            $heading{'assign'} =
              ($sort_flag)
              ? "<a href=\"?${shwdvd}sort=assign&desc=0\"><font color=\"#df9700\">Assigned</font></a>"
              : "<a href=\"?${shwdvd}sort=assign&desc=1\"><font color=\"#df9700\">Assigned</font></a>";
        }
        elsif ( $sort_by eq '' && $cat_name !~ m/-Sprint$/ ) {
            $order_by = "t.version $sort_direction, t.priority DESC, s.status, t.title";
            $heading{'version'} =
              ($sort_flag)
              ? "<a href=\"?${shwdvd}sort=version&desc=0\"><font color=\"#df9700\">Version</font></a>"
              : "<a href=\"?${shwdvd}sort=version&desc=1\"><font color=\"#df9700\">Version</font></a>";
        }
        elsif ( $sort_by eq 'prio' ) {
            $sort_direction = ( $sort_direction eq 'ASC' ) ? 'DESC' : 'ASC';
            $order_by = "t.priority $sort_direction, s.status DESC, t.title";
            $heading{'prio'} =
              ($sort_flag)
              ? "<a href=\"?${shwdvd}sort=prio&desc=0\"><font color=\"#df9700\">Priority</font></a>"
              : "<a href=\"?${shwdvd}sort=prio&desc=1\"><font color=\"#df9700\">Priority</font></a>";
        }
        elsif ( $sort_by eq 'version' ) {
            $order_by = "t.version $sort_direction";
            $heading{'version'} =
              ($sort_flag)
              ? "<a href=\"?${shwdvd}sort=version&desc=0\"><font color=\"#df9700\">Version</font></a>"
              : "<a href=\"?${shwdvd}sort=version&desc=1\"><font color=\"#df9700\">Version</font></a>";
        }
        elsif ( $sort_by eq 'title' ) {
            $order_by = "t.title $sort_direction";
            $heading{'title'} =
              ($sort_flag)
              ? "<a href=\"?${shwdvd}sort=title&desc=0\"><font color=\"#df9700\">Task</font></a>"
              : "<a href=\"?${shwdvd}sort=title&desc=1\"><font color=\"#df9700\">Task</font></a>";
        }
        elsif ( $sort_by eq 'tid' ) {
            $order_by = "t.id $sort_direction";
            $heading{'tid'} =
              ($sort_flag)
              ? "<a href=\"?${shwdvd}sort=tid&desc=0\"><font color=\"#df9700\">ID</font></a>"
              : "<a href=\"?${shwdvd}sort=tid&desc=1\"><font color=\"#df9700\">ID</font></a>";
        }
        elsif ( $sort_by eq 'status' ) {
            $order_by = "s.status $sort_direction, t.priority DESC, t.title";
            $heading{'status'} =
              ($sort_flag)
              ? "<a href=\"?${shwdvd}sort=status&desc=0\"><font color=\"#df9700\">Status</font></a>"
              : "<a href=\"?${shwdvd}sort=status&desc=1\"><font color=\"#df9700\">Status</font></a>";
        }
        elsif ( $sort_by eq 'grpldr' ) {
            $sort_direction = ( $sort_direction eq 'ASC' ) ? 'DESC' : 'ASC';
            $order_by = "sup.username $sort_direction, t.priority DESC, t.title";
            $heading{'grpldr'} =
              ($sort_flag)
              ? "<a href=\"?${shwdvd}sort=grpldr&desc=0\"><font color=\"#df9700\">Supervisor</font></a>"
              : "<a href=\"?${shwdvd}sort=grpldr&desc=1\"><font color=\"#df9700\">Supervisor</font></a>";
        }
        elsif ( $sort_by eq 'assign' ) {
            $order_by = "dev.username $sort_direction, t.priority DESC, t.title";
            $heading{'assign'} =
              ($sort_flag)
              ? "<a href=\"?${shwdvd}sort=assign&desc=0\"><font color=\"#df9700\">Assigned</font></a>"
              : "<a href=\"?${shwdvd}sort=assign&desc=1\"><font color=\"#df9700\">Assigned</font></a>";
        }

        my $limit;
        if ($master) {
            $limit = '';
        }
        else {
            my $low =
              ( defined $cgi->param('lim') and $cgi->param('lim') > 0 ) 
              ? 15 * $cgi->param('lim') - 15
              : 0;
            my $high = $low + 15;
            $limit =
              ( ($cgi->param('lim') || '') eq 'all' ) 
              ? ''
              : "LIMIT $low,$c{misc}{view_limit}";
        }

        my $archtask = ( $cgi->param('archtask') ) ? '&archtask=1' : '';
        my $statement = '';
        my $sth2;
        if ($show_devid) {
            $statement =
                "SELECT DISTINCT t.id, t.version, t.supervisor, sup.username, dev.username, t.title, t.priority, s.status "
              . "  FROM tasks t, status s, user dev, user sup "
              . "    WHERE t.cat_id =  ? "
              . "      AND t.arch   =  ? "
              . "      AND s.id     =  t.status "
              . "      AND t.developer =  ? "
              . "      AND dev.id     =  t.developer "
              . "      AND sup.id     =  t.supervisor "
              . "    ORDER BY $order_by $limit";
            $sth2 = $dbh->prepare($statement);
            $sth2->execute( $cat_id, $vflag, $show_devid );
        }
        else {
            $statement =
                "SELECT DISTINCT t.id, t.version, t.supervisor, sup.username, dev.username, t.title, t.priority, s.status "
              . "  FROM tasks t, status s, user dev, user sup "
              . "    WHERE t.cat_id =    ? "
              . "      AND t.arch   =    ? "
              . "      AND s.id     =    t.status "
              . "      AND dev.id   =    t.developer "
              . "      AND sup.id   =    t.supervisor "
              . "    ORDER BY $order_by $limit";
            $sth2 = $dbh->prepare($statement);
            $sth2->execute( $cat_id, $vflag );
        }

        my $colhead =
            "<tr>"
          . "<td valign=top>"                   . ( ( $rib && field_hidden 'priority' ) ? "&#160;" : "<font size=\"-1\"><b><em>$heading{'prio'}</em></b></font>" )
          . "</td><td valign=top>"              . ( ( $rib && field_hidden 'version' )  ? "&#160;" : "<font size=\"-1\"><b><em>$heading{'version'}</em></b></font>" )
          . "</td><td valign=top>"              . ( ( $rib && field_hidden 'title' )    ? "&#160;" : "<font size=\"-1\"><b><em>$heading{'title'}</em></b></font>" )
          . "</td><td valign=top align=center>" . ( ( $rib && field_hidden 'tid' )      ? "&#160;" : "<font size=\"-1\"><b><em>$heading{'tid'}</em></b></font>" )
          . "</td><td valign=top>"              . ( ( $rib && field_hidden 'status' )   ? "&#160;" : "<font size=\"-1\"><b><em>$heading{'status'}</em></b></font>" )
          . "</td><td valign=top>"              . ( ( $rib && field_hidden 'groupldr' ) ? "&#160;" : "<font size=\"-1\"><b><em>$heading{'grpldr'}</em></b></font>" )
          . "</td><td valign=top>"              . ( ( $rib && field_hidden 'assigned' ) ? "&#160;" : "<font size=\"-1\"><b><em>$heading{'assign'}</em></b></font>" )
          . "</td><td valign=top>"              . ( ( $rib && field_hidden 'queue' )    ? "&#160;" : "<font size=\"-1\"><b><em>$heading{'queue'}</em></b></font>" )
          . "</td></tr>"
          ;

        $html_page .= "<tr><td colspan=9 width=\"100%\">" . mk_title( $cat_name, 1 ) . "</td></tr>$colhead\n"
          if ( $sth2->rows );

        my $cnt = 0;
        while ( my ( $id, $version, $grpldr, $grp_name, $dev_name, $title, $prio, $status ) = $sth2->fetchrow_array ) {
            my $cprio    = &priority_color($prio);
            $version |= '';
            $dev_name |= '';
            $grp_name |= '';
            my $has_seen = has_seen( $id, get_current_id() );
            $title =
              ($has_seen) 
              ? "<font color=\"$c{color}{mysqlblu}\">$title</font>"
              : "<font color=\"$c{color}{mysqlblu}\"><b>$title</b></font>";
            my $statement = '';
            my $sth = '';

            my $trcolor =
              ( !( $cnt % 2 ) ) 
              ? "bgcolor=$c{color}{ltgreen}"
              : "bgcolor=white";
            $cnt++;
            $html_page .=
                "<form method=\"get\" name=\"myform\" action=\"forms.pl\">\n"
              . "<tr $trcolor width=\"100%\">\n"
              . "<!--<td>&#160;&#160;&#160;</td>-->\n"
              . "<td width=\"9%\" align=center>"
              ;
            if ( $rib && field_hidden 'priority' ) {
                $html_page .= "&#160;";
            }
            else {
                $html_page .= "<font size=\"-1\"> <input type=\"hidden\" name=\"tid\" value=\"$id\"><input type=\"hidden\" name=\"form\" value=\"chprio\"><input type=\"hidden\" name=\"old_prio\" value=\"$prio\"><input type=\"text\" name=\"prio\" value=\"$prio\" size=3 maxlength=2> </font>";
            }

            $html_page .= "</td>\n"
              . "<!--<td width=1>&#160;</td>-->\n"
              . "<td width=\"9%\">"
              ;

            if ( $rib && field_hidden 'version' ) {
                $html_page .= "&#160;";
            }
            else {
                $html_page .="<font size=\"-1\">\n"
                  . "<select style=\"width: 60px\" name=\"version_select\" onChange=\"window.location.href = this.options[this.selectedIndex].value\">\n"
                  ;
                foreach my $item ( sort keys %{ $c{misc}{versions} } ) {
                    my $greatestver = ( @{ $c{misc}{versions}{$item} }[0] );
                    $html_page .= "<option value=\"forms.pl?form=chversion&list=1&tid=$id&version=$item-$greatestver\">$item</option>\n";
                    foreach my $itemver ( @{ $c{misc}{versions}{$item} } ) {
                        my $sel =
                        ( $version eq "$item-$itemver" ) ? " selected" : "";
                        $html_page .= "<option value=\"forms.pl?form=chversion&list=1&tid=$id&version=$item-$itemver\"$sel>  $itemver</option>\n";
                    }
                }
                $html_page .= "</select></font>";
            }

            $html_page .= "</td>\n"
              . "<!--<td width=1>&#160;</td>-->\n"
              . "<td width=\"56%\"><font size=\"-1\"> <a href=\"$url?tid=${id}$archtask\">$title</a> </font></td>\n"
              . "<!--<td width=1>&#160;</td>-->\n"
              . "<td width=\"4%\" align=right valign=middle><font size=\"-1\"> ${id}&#160;</font></td>\n"
              . "<!--<td width=1>&#160;</td>-->\n"
              . "<td width=\"10%\">"
              ;

            if ( $rib && field_hidden 'status' ) {
                $html_page .= "&#160;";
            }
            else {
                $html_page .= "<font size=\"-1\">\n<select style=\"width: 60px\" name=\"stat_select\" onChange=\"window.location.href = this.options[this.selectedIndex].value\">\n";

                $statement = "SELECT id, status FROM status ORDER BY status";
                $sth       = $dbh->prepare($statement);
                $sth->execute;

                while ( my $res = $sth->fetchrow_arrayref ) {
                    my $sel = ( $res->[1] eq $status ) ? " selected" : "";
                    $html_page .= "<option value=\"forms.pl?form=chstatus&list=1&status=$res->[1]&tid=$id\"$sel>$res->[1]</option>\n";
                }

                $html_page .= "</select></font>";
            }


            $html_page .= "</td>\n"
              . "<!--<td width=1>&#160;</td>-->\n"
              . "<td width=\"11%\">"
              ;

            if ( $rib && field_hidden 'groupldr' ) {
                $html_page .= "&#160;";
            }
            else {
                $html_page .= "<font size=\"-1\"><select style=\"width: 60px\" name=\"grpldr_select\" onChange=\"window.location.href = this.options[this.selectedIndex].value\">\n";
                $statement = "SELECT id, username FROM user WHERE grpldr='y' ORDER BY username";
                $sth = $dbh->prepare($statement);
                $sth->execute;
                my $grpar_dev = $sth->fetchall_arrayref;
                foreach my $res ( @{$grpar_dev} ) {
                    my $sel = ( $grpldr == $res->[0] ? " selected" : "" );
                    $html_page .= "<option value=\"forms.pl?form=chgrpldr&list=1&tid=$id&grpldr=$res->[0]\"$sel>$res->[1]</option>\n";
                }
                $html_page .= "</select></font>";
            }

            $html_page .= "</td>\n"
              . "<!--<td width=1>&#160;</td>-->\n"
              . "<td width=\"12%\">"
              ;
            if ( $rib && field_hidden 'assigned' ) {
                $html_page .= "&#160;";
            }
            else {
                $html_page .= "<font size=\"-1\">$dev_name</font>";
            }
            
            $html_page .= "</td>\n"
              . "<!--<td width=1>&#160;</td>-->\n"
              . "<td width=\"10%\"><font size=\"-1\">\n"
              . "<select style=\"width: 60px\" name=\"category_select\" onChange=\"window.location.href = this.options[this.selectedIndex].value\">\n"
              ;

            my @cn1 = split /-/, $cat_name;
            $statement = "SELECT id, name FROM categories WHERE name LIKE '${cn1[0]}-%' ORDER BY name";
            $sth = $dbh->prepare($statement);
            $sth->execute;

            while ( my $res = $sth->fetchrow_arrayref ) {
                my $sel = ( $res->[1] eq $cat_name ) ? " selected" : "";
                $html_page .= "<option value=\"forms.pl?form=chcate&list=1&tid=$id&cate=$res->[1]\"$sel>$res->[1]</option>\n";
            }

            $html_page .=
                "</select></td>\n"
              . "</tr>\n"
              . "</form>\n"
              ;
        }
    }

    if ( !$master ) {
        my $statement = '';
        my $sth2;
        if ($show_devid) {
            $statement =
                "SELECT CEILING(count(t.id)/$c{misc}{view_limit})"
              . "  FROM tasks t, categories c"
              . "    WHERE t.cat_id  =  c.id"
              . "      AND t.arch    =  'n'"
              . "      AND c.name    =  ?"
              . "      AND t.developer  =  ?"
              ;
            $sth2 = $dbh->prepare($statement);
            $sth2->execute( $catname, $show_devid );
        }
        else {
            $statement =
                "SELECT CEILING(count(t.id)/$c{misc}{view_limit})"
              . "  FROM tasks t, categories c"
              . "    WHERE t.cat_id = c.id"
              . "      AND t.arch = 'n'"
              . "      AND c.name = ?"
              ;
            $sth2 = $dbh->prepare($statement);
            $sth2->execute( $catname );
        }

        my ($numtasks) = $sth2->fetchrow_array;

        my @params = $cgi->param;

        my $newparams = '?';

        foreach my $param ( $cgi->param ) {
            next if ( $param eq 'catname' );
            next if ( $param eq 'lim' );
            $newparams .= "$param=" . $cgi->param($param) . "&";
        }

        $html_page .= "<tr><td align=center colspan=9><br><b>Result page: </b>";
        my $lim =
          ( ($cgi->param('lim') || '') eq 0 || ($cgi->param('lim') || '') eq '' ) 
          ? 1
          : $cgi->param('lim');
        for ( my $i = 1 ; $i <= $numtasks ; $i++ ) {
            $html_page .= ( $i eq $lim ) 
              ? "<font color=red>$i</font>"
              : "<a href=\"${newparams}lim=$i\">$i</a>";
            $html_page .= '&#160;';
        }

        my $limall =
          ( ($cgi->param('lim') || '') eq 'all' ) 
          ? '<font color=red>All</font>'
          : "<a href=\"${newparams}lim=all\">All</a>";

        $html_page .= "&#160;$limall";
    }
    $html_page .= "</td></tr></table>\n";

    $html_page .= page_end('tasks');

    print $html_page;
}

sub _view_tasks_nocat {
    my ($view) = @_;
    my $html_page = page_start("Queues");
    $html_page .= table_start( 'minimal', { actions => 1, main => 1, view => $view, vflag => $view } );

    $html_page .=
          "<table width=\"100%\" cellspacing=2 cellpadding=2 border=0>\n"
        . "<tr><td colspan=3>\n"
        ;
    $html_page .= mk_title( "Software Development WorkLog", 1 );

    $html_page .= "</td></tr><tr><th>";
    $html_page .= mk_title("RawIdeaBins");
    $html_page .= "</th><th>";
    $html_page .= mk_title("BackLogs");
    $html_page .= "</th><th>";
    $html_page .= mk_title("Sprints");
    $html_page .= "</th></tr><tr>";

    my %all_numtasks = (
        'ideabin' => 0,
        'backlog' => 0,
        'sprint'  => 0,
    );

    foreach my $cattype ( 'RawIdeaBin', 'BackLog', 'Sprint' ) {
        my $statement =
            "SELECT id, name FROM categories WHERE name like "
            . "'%$cattype' ORDER BY name";
        my $sth = $dbh->prepare($statement);
        $sth->execute;

        $html_page .= "<td><ul>\n";

        while ( my ( $cat_id, $cat_name ) = $sth->fetchrow_array ) {
            my $statement =
                "SELECT count(id) FROM tasks WHERE cat_id = ? AND arch = 'n'";
            my $sth2 = $dbh->prepare($statement);
            $sth2->execute($cat_id);

            my ($numtasks) = $sth2->fetchrow_array;

            if ( $cat_name =~ m/^.+\-RawIdeaBin$/ ) {
                $all_numtasks{'ideabin'} += $numtasks;
            }
            elsif ( $cat_name =~ m/^.+\-BackLog$/ ) {
                $all_numtasks{'backlog'} += $numtasks;
            }
            elsif ( $cat_name =~ m/^.+\-Sprint$/ ) {
                $all_numtasks{'sprint'} += $numtasks;
            }

            my $short_cat_name = '';
            ($short_cat_name = $cat_name) =~ s/-$cattype//;
            $html_page .= "<li><a href=\"$cat_name/\"><font color=\"$c{color}{mysqlblu}\">$short_cat_name</font></a> <font color=black size=\"-1\">($numtasks)</font>\n";
        }
        $html_page .= "</ul></td>\n";
    }

    $html_page .=
          "<tr>\n"
        . "<td><ul><li><a href=\"MASTER-RawIdeaBin/\"><font color=\"$c{color}{mysqlblu}\">MASTER</a> <font color=black size=\"-1\">($all_numtasks{ideabin})</font></ul></td>\n"
        . "<td><ul><li><a href=\"MASTER-BackLog/\"><font color=\"$c{color}{mysqlblu}\">MASTER</a> <font color=black size=\"-1\">($all_numtasks{backlog})</font></ul></td><td><ul><li><a href=\"MASTER-Sprint/\"><font color=\"$c{color}{mysqlblu}\">MASTER</a> <font color=black size=\"-1\">($all_numtasks{sprint})</font></ul></td></tr>\n"
        ;

    $html_page .= "<tr><th colspan=3>";
    $html_page .= mk_title("Other Queues not in SCRUM");
    $html_page .= "</th></tr><tr>";

    my $statement =
        "SELECT id, name FROM categories WHERE name NOT LIKE "
        . "'%RawIdeaBin' AND name NOT LIKE '%BackLog' AND name NOT LIKE '%Sprint' ORDER BY name";
    my $sth = $dbh->prepare($statement);
    $sth->execute;

    $html_page .= "<td colspan=3><ul>\n";
    while ( my ( $cat_id, $cat_name ) = $sth->fetchrow_array ) {
        my $statement =
            "SELECT count(id) FROM tasks WHERE cat_id = ? AND arch = 'n'";
        my $sth2 = $dbh->prepare($statement);
        $sth2->execute($cat_id);

        my ($numtasks) = $sth2->fetchrow_array;
        $html_page .= "<li><a href=\"$cat_name/\"><font color=\"$c{color}{mysqlblu}\">$cat_name</font></a> <font color=$c{color}{black} size=\"-1\">($numtasks)</font>\n";
    }
    $html_page .= "</ul></td></tr></table>\n";

    $html_page .= page_end('tasks');

    return $html_page;
}

########################################################################
######## Viewing one task

sub _view_task {
    my $tid   = shift;
    my $view  = ( $cgi->param('archtask') ) ? 'archived' : 'active';
    my $vflag = ( $view eq 'active' ) ? 'n' : 'y';
    $view = ( is_arch_ready($tid) ) ? 'archived' : 'active';
    my $rib = get_catname($tid) =~ /-RawIdeaBin$/;

    start:
    my $statement =
        "SELECT owner, t.supervisor, creator, own.email, title, description, hilevelarch, loleveldesign, "
        . "DATE_FORMAT(creation_date, '%a, %d %b %Y, %H:%i'), "
        . "st.status, priority, cat.name, version, t.developer, DATE_FORMAT(t.dev_complete_date, '%a, %d %b %Y, %H:%i'), "
        . "t.designer, t.designrev, DATE_FORMAT(t.desrev_complete_date, '%a, %d %b %Y, %H:%i'), t.coderev1, DATE_FORMAT(t.coderev1_complete_date, '%a, %d %b %Y, %H:%i'), "
        . "t.coderev2, DATE_FORMAT(t.coderev2_complete_date, '%a, %d %b %Y, %H:%i'), t.qa, DATE_FORMAT(t.qa_complete_date, '%a, %d %b %Y, %H:%i'), t.doc, DATE_FORMAT(t.doc_complete_date, '%a, %d %b %Y, %H:%i') "
        . "FROM tasks t, user own, status st, categories cat WHERE t.id = ? "
        . "AND owner = own.id AND t.status = st.id AND cat_id = cat.id AND t.arch = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute( $tid, $vflag );

    my (
        $owner, $grpldr, $creator, $owner_email, $title, $descrip, $hla, $lld, $crdate, $status,
        $prio, $catname, $version, $developer, $dev_done_date, $designer, $designrev,
        $designrev_done_date, $coderev1, $coderev1_done_date, $coderev2, $coderev2_done_date,
        $qa, $qa_done_date, $documentation, $doc_done_date
      )
      = $sth->fetchrow_array;
    $title ||= '';
    my $dactu = "0000-00-00";

    $version |= '';
    $version =~ s/\s*//g;

    # $title = quotemeta($title);
    if ( $title eq '' && $vflag eq 'y' ) {
        error("$c{err}{noid} Task: $tid");
    }
    elsif ( $title eq '' ) {
        $vflag = 'y';
        goto start;
    }
    else {
        my $cprio = priority_color($prio);
        # my $owner_str = owner_html( $owner, $enteredby, $tid );
        my $creator_str = creator_html($creator);
        # my $devs = join( ', ', personlist_html( $tid, "developer" ));
        # my $coderevs = join( ', ', personlist_html( $tid, "codereview" ));
        my ($shortcrdate) = $crdate=~ /, (.*?),/;
        my $version_str = $version;
        my %headings = (
            timeest => "Time Estimates",
            depends => "Task Dependencies",
            file    => "File Attachments",
            hld     => "High-Level Description",
            hla     => "High-Level Specification",
            lld     => "Low-Level Design",
            progress => "Progress Reports",
        );
        my @heading_order = qw( timeest depends file hld hla lld progress );
        my @heading_html = ();
        for (@heading_order) {
            push @heading_html, "<a href=\"#$_\">$headings{$_}</a>";
        }

        my $html_page   = page_start("$catname: $title");
        $html_page .= table_start( 'normal', { actions => 1, tid => $tid, did => get_current_id, view => 'both', vflag => $view } );
        $html_page .= join("&nbsp;|&nbsp;", @heading_html) . "<br><br>";
        $html_page .= mk_title( "$title", 1 );

        $title =~ s/"/&quot;/g;
        $html_page .=
            "<form method=\"post\" action=\"$c{misc}{baseurl}forms.pl\">\n"
          . "<table width=\"100%\" border=0>\n"
          . "<tr><td valign=top width=\"45%\">\n"
          . "<table width=\"100%\" border=0>\n"
          . "<!-- <form method=\"post\" action=\"forms.pl\"> -->\n"
          . "<tr><th align=\"right\">Title</th><td><input type=\"hidden\" name=\"tid\" value=\"$tid\"><input type=\"hidden\" name=\"old_title\" value=\"$title\"><input type=text name=title value=\"$title\" size=30 maxlength=255></td></tr>\n"
          . "<!-- </form> -->\n"
          . "<tr><th align=\"right\">Task ID</th><td>$tid</td></tr>\n"
          ;

        # Category-Queue
            $html_page .= "</td></tr>\n"
              . "<tr><th align=\"right\">Queue</th><td>\n"
              . "<input type=\"hidden\" name=\"old_category\" value=\"$catname\">\n"
              . "<select style=\"width: 120px\" name=\"category_select\">\n"
              ;

            $statement = "SELECT id, name FROM categories ORDER BY name";
            $sth       = $dbh->prepare($statement);
            $sth->execute;

            while ( my $res = $sth->fetchrow_arrayref ) {
                my $sel = ( $res->[1] eq $catname ) ? " selected" : "";
                $html_page .= "<option value=\"$res->[1]\"$sel>$res->[1]</option>\n";
            }

        # Version
            my ($projectname) = $catname =~ /^(.+)-/;
            $html_page .=
                "</select></td></tr>\n"
              . "<tr><th align=\"right\">Version</th><td>\n"
              ;

            if ( $rib && field_hidden 'version' ) {
                $html_page .= "N/A";
            }
            else {
                $html_page .= "<input type=\"hidden\" name=\"old_version\" value=\"$version\">\n"
                  . "<select style=\"width: 120px\" name=\"version_select\">\n"
                  # . "<option></option>\n"
                  ;
                my $version_category = $c{misc}{default_versions}{$projectname};
                # my $greatestver = ( @{ $c{misc}{versions}{$version_category} }[0] );
                # $html_page .= "<option value=\"$version_category-$greatestver\">$version_category</option>\n";
                foreach my $itemver ( @{ $c{misc}{versions}{$version_category} } ) {
                    my $sel = ( $version eq "$version_category-$itemver" ) ? " selected" : "";
                    $html_page .= "<option value=\"$version_category-$itemver\"$sel>$version_category - $itemver</option>\n";
                }

                $html_page .= "</select>";
            }

        # Status
            $html_page .= "</td></tr>\n"
              . "\n"
              . "<tr><th align=\"right\">Status</th><td>\n"
              ;

            if ( 0 && $rib && field_hidden 'status' ) {
                $html_page .= "N/A";
            }
            else {
                $html_page .= "<input type=\"hidden\" name=\"old_stat\" value=\"$status\">\n"
                  . "<select style=\"width: 120px\" name=\"stat_select\">\n"
                  ;

                $statement = "SELECT id, status FROM status ORDER BY status";
                $sth       = $dbh->prepare($statement);
                $sth->execute;

                while ( my $res = $sth->fetchrow_arrayref ) {
                    my $sel = ( $res->[1] eq $status ) ? " selected" : "";
                    $html_page .= "<option value=\"$res->[1]\"$sel>$res->[1]</option>\n";
                }

                $html_page .= "</select>";
            }

        # Priority
            $html_page .= "</td></tr>\n"
              . "<tr><th align=\"right\">Priority</th><td>"
              ;
              
            if ( $rib && field_hidden 'priority' ) {
                $html_page .= "N/A";
            }
            else {
                $html_page .= "<input type=\"hidden\" name=\"old_prio\" value=\"$prio\">"
                  . "<input type=text style='color: $cprio' name=prio value=\"$prio\" size=3 maxlength=2>"
            }

        # Copies to
            my $obs = '';
            $statement = 
                "SELECT u.id, u.username FROM user u, observers o"
                . " WHERE u.id = o.dev_id"
                . "   AND o.task_id = ?"
                ;
            $sth = $dbh->prepare($statement);
            $sth->execute($tid);
            while (my ($id, $name) = $sth->fetchrow_array) {
                # $obs .= "$name<a href=\"$c{misc}{baseurl}forms.pl?form=removeobs&tid=$tid&devid=$id\"><img src=\"$c{misc}{baseurl}images/delete.jpg\" width=23 height=21></a><br>";
                $obs .= "$name<br>";
            }
            $html_page .= "</td></tr>\n";
            $html_page .=
                "<tr><th align=\"right\" valign=\"top\">Copies to</th><td>"
              . $obs . "<a href=\"forms.pl?form=observ&tid=$tid\">Modify...</a><br>"
              . "</td></tr>\n"
              ;
            $html_page .= "</table></td>\n";
          
        # Second column
        $html_page .= 
            "<td valign=top width=\"55%\">\n"
          . "<table width=\"100%\" border=0>\n"
          . "<tr><th align=\"right\">Created by</th><td>$creator_str</td>"
          . "<td><abbr title=\"$crdate\">$shortcrdate</abbr></td><th>Done</th></tr>\n"
          . "<tr><th align=\"right\">Supervisor</th><td>\n"
          ;

        # Supervisor
            if ( $rib && field_hidden 'groupldr') {
                $html_page .= "N/A";
            }
            else {
                $html_page .=
                    "<input type=\"hidden\" name=\"old_grpldr\" value=\"$grpldr\">\n"
                  . "<select style=\"width: 120px\" name=\"grpldr_select\">\n"
                  ;
                $statement =
                "SELECT id, username FROM user WHERE grpldr='y' ORDER BY username";
                $sth = $dbh->prepare($statement);
                $sth->execute;
                my $grpar_dev = $sth->fetchall_arrayref;
                foreach my $res ( @{$grpar_dev} ) {
                    my $sel = ( $grpldr == $res->[0] ? " selected" : "" );
                    $html_page .= "<option value=\"$res->[0]\"$sel>$res->[1]</option>\n";
                }

                $html_page .= "</select>";
            }
        $html_page .= "</td><td>&nbsp;</td><td>&nbsp;</td>\n";

        # Lead Architect (designer)
        $html_page .= html_role_assignment('Lead Architect', 'designer', $designer, 'n/a');

        # Architecture Reviewer (designrev) / designrev_done_date
        $html_page .= html_role_assignment('Architecture Review', 'designrev', $designrev, $designrev_done_date);

        # Implementor (developer) / (dev_done_date)
        $html_page .= html_role_assignment('Implementor', 'developer', $developer, $dev_done_date);

        # 1st Code Review (coderev1) / (coderev1_done_date)
        $html_page .= html_role_assignment('1st Code Review', 'coderev1', $coderev1, $coderev1_done_date);

        # 2nd Code Review (coderev2) / (coderev2_done_date)
        $html_page .= html_role_assignment('2nd Code Review', 'coderev2', $coderev2, $coderev2_done_date);

        # QA (qa) / (qa_done_date)
        $html_page .= html_role_assignment('QA', 'qa', $qa, $qa_done_date);

        # Documentation (documentation) / (doc_done_date)
        $html_page .= html_role_assignment('Documentation', 'doc', $documentation, $doc_done_date);

        $html_page .=
            "</table>\n"
          . "</td></tr>\n"
          . "<tr><td valign=top colspan=2 align=center>\n"
          . "    <input type=\"hidden\" name=\"form\" value=\"chtask\">\n"
          . "    <input type=reset value=\"Reset Form\">\n"
          . "    <input type=submit value=\"Commit All Changes\" style=\"background-color: #f0f0f0\">\n"
          . "</form>\n"
          . "</td></tr></table>\n"
          ;

        # Time Estimates
        $html_page .=
            "<table width=100% border=0><tr><td valign=top align=left>\n"
            . "<tr><td>\n"
            . "<a name=\"timeest\"></a>"
            . mk_title("Time Estimates")
            . "</td></tr>\n"
            . "<tr><td>\n\n\n"
            ;

        # -- form two columns within Time Estimates box
        $html_page .=
            "<table width=100% border=0><tr>"
            . "<td width=35% valign=top>"
            ;

        # ---- build top of lefthand time worked box
        $html_page .=
            "<table width=100% border=0><tr>"
            . "<th width=45%><u>Name</u></th>"
            . "<th width=20%><u>Hours Worked</th>"
            . "<th width=35%><u>Last Updated</th>"
            . "</tr>\n"
            ;

        $statement =
            "SELECT tl.dev_id, u.username, SUM(tl.hrs_worked), DATE_FORMAT(MAX(tl.recorded),'%d %b %Y')"
            . "           FROM timelog tl, user u"
            . "          WHERE tl.task_id = ?"
            . "            AND tl.dev_id = u.id"
            . "          GROUP BY tl.dev_id"
            . "          ORDER BY u.username"
            ;
        $sth = $dbh->prepare($statement);
        $sth->execute($tid);
        my $ttl_hrsworked = 0;
        while ( my $res = $sth->fetchrow_arrayref ) {
            my ($devid, $devname, $worked, $date) = @$res;
            next unless $worked > 0;

            $ttl_hrsworked += $worked;
            $html_page .=
                "<tr valign=baseline>"
                . "<td align=left>$devname</td>"
                . "<td align=right>$worked</td>"
                . "<td align=right>$date</td>"
                . "</tr>"
                ;
        }
        my $ttl_hrsworked_thistask = $ttl_hrsworked;

        # ---- -- Calculate subtask total and grand total
        my @children = all_children_of($tid);
        if (@children) {
            my $children_list = join ', ', @children;
            $statement = "SELECT SUM(hrs_worked) FROM timelog WHERE task_id IN ($children_list)";
            $sth       = $dbh->prepare($statement);
            $sth->execute;
            if ( my $res = $sth->fetchrow_arrayref ) {
                my ( $worked ) = @$res;
                $ttl_hrsworked += $worked;
                $html_page .=
                    "<tr valign=baseline>"
                    . "<th align=left>All Sub Tasks</th>"
                    . "<th align=right>$worked</th>"
                    . "<td align=right>&nbsp;</td>"
                    . "</tr>"
                    ;
            }
        }
        $html_page .=
            "<tr valign=baseline>"
            . "<th align=left>Total</th>"
            . "<th align=right>$ttl_hrsworked</th>"
            . "<td align=right>&nbsp;</td>"
            . "</tr>"
            ;


        # ---- close lefthand time worked box
        $html_page .=
            "</table></td>"
            . "<td width=1 bgcolor=black></td>"
            . "<td width=65% valign=top>"
            ;

        # ---- build top of righthand time remaining box
        $html_page .=
            "<table width=100% border=0><tr>"
            . "<th width=20%>&nbsp;</th>"
            . "<th width=10%><u>Hrs Worked</u></th>"
            . "<th width=50%><u>Progress</u></th>"
            . "<th width=10%><u>Current</u></th>"
            . "<th width=10%><u>Original</u></th>"
            . "</tr>\n"
            ;

        my $ttl_hrsworked_subtasks = $ttl_hrsworked - $ttl_hrsworked_thistask;

        # - get current estimate for this task
            $statement =
                "SELECT SUM(estimate_delta)"
                . "  FROM timelog"
                . " WHERE task_id = ?"
                ;
            $sth = $dbh->prepare($statement);
            $sth->execute($tid);
            my ($hrs_remain_thistask) = $sth->fetchrow_array;

        # - get original estimate for this task
            $statement =
                "SELECT estimate_delta"
                . "  FROM timelog"
                . " WHERE task_id = ?"
                . "   AND estimate_delta > 0"
                . " ORDER BY recorded"
                . " LIMIT 1"
                ;
            $sth = $dbh->prepare($statement);
            $sth->execute($tid);
            my ($orig_hrs_remain_thistask) = $sth->fetchrow_array;
            $orig_hrs_remain_thistask |= 0;

        my $hrs_remain_subtasks = 0;
        my $orig_hrs_remain_subtasks = 0;
        if (@children) {
            my $children_list = join ', ', @children;

            # - get current estimate for all sub tasks
            $statement =
                "SELECT SUM(estimate_delta)"
                . "  FROM timelog"
                . " WHERE task_id IN ($children_list)"
                ;
            $sth = $dbh->prepare($statement);
            $sth->execute;
            ($hrs_remain_subtasks) = $sth->fetchrow_array;

            # - get original estimate for all sub tasks
            $statement = 
                "SELECT estimate_delta"
                . "  FROM timelog"
                . " WHERE task_id = ?"
                . "   AND estimate_delta > 0"
                . " ORDER BY recorded"
                . " LIMIT 1"
                ;
            $sth = $dbh->prepare($statement);
            foreach (@children) {
                $sth->execute($_);
                my ($estimate) = $sth->fetchrow_array;
                $orig_hrs_remain_subtasks += $estimate || 0;
            }

        }

        my @estimates = (
            [ 'This Task', $ttl_hrsworked_thistask, $hrs_remain_thistask, $orig_hrs_remain_thistask ],
            [ 'Sub Tasks', $ttl_hrsworked_subtasks, $hrs_remain_subtasks, $orig_hrs_remain_subtasks ],
        );
        my $html_template =
            '<tr><t$dh align=left>$label</t$dh>'
            . '<t$dh align=right>$worked</t$dh>'
            . '<td align=right valign=middle>'
            .   '<img src=\"$c{misc}{baseurl}images/black.gif\" width=$pctdone height=10>'
            .   '<img src=\"$c{misc}{baseurl}images/silver.gif\" width=$pctremain height=10>'
            . '</td>'
            . '<t$dh align=right>$remain</t$dh>'
            . '<t$dh align=right>$orig</t$dh>'
            . '</tr>\n'
            ;

        my ($ttl_worked, $ttl_remain, $ttl_orig) = (0,0,0);
        foreach (@estimates) {
            my ($label, $worked, $remain, $orig) = @$_;
            $ttl_worked += $worked;
            $ttl_remain += $remain;
            $ttl_orig   += $orig;
            my $dh = 'd';
            my ($pctdone, $pctremain) = percentages($worked, $remain);
            next if $worked == 0 && $remain == 0 && $orig == 0;
            $html_page .= eval "return \"$html_template\"";
        }
        {
            my ($label, $worked, $remain, $orig) = 
                ('Total', $ttl_worked, $ttl_remain, $ttl_orig);
            my $dh = 'h';
            my ($pctdone, $pctremain) = percentages($worked, $remain);
            $html_page .= eval "return \"$html_template\"";
        }

        $html_page .= "<tr><td>&nbsp;</td></tr><tr><td colspan=5 align=center>";
        $html_page .= "&#160;" . mk_button( "Add Progress Report", "index.pl?tid=$tid&progrep=1#progress" )
            unless $cgi->param('progrep');
        $html_page .= "</td></tr>";

        # ---- close righthand time remaining box
        $html_page .= "</table></td></tr>\n";

        # -- close time estimates
        $html_page .=
            "</table>"
          . "</td></tr></table>\n";

        # Dependency header
        $html_page .=
            "<table width=100%><tr><td valign=top align=left>\n"
          . "<tr><td>\n"
          . "<a name=\"depends\"></a>"
          . mk_title("Task Dependencies")
          . "</td></tr>\n"
          . "<tr><td>\n\n\n"
          ;

        $html_page .=
            "<table width=100%><tr>"
          . "<th valign=top align=left width=50%><u>Others waiting for Task $tid</u></th>"
          . "<th valign=top align=left width=50%><u>Task $tid is waiting for</u></th></tr>"
          ;

        $html_page .= "<tr valign=top><td><table width=100%>";

        # Reverse depends
        $statement = "SELECT d.parent, t.title FROM depends d, tasks t WHERE d.child = ? AND d.parent = t.id";
        $sth       = $dbh->prepare($statement);
        $sth->execute($tid);
        while ( my $res = $sth->fetchrow_arrayref ) {
            my ($id, $title) = @$res;
            $html_page .=
                  "<tr>"
                . "<td width=10% align=right>$id</td>"
                . "<td width=5>&nbsp;</td>"
                . "<td><a href=\"$c{misc}{baseurl}index.pl?tid=$id\">$title</a></td>"
                . "</tr>\n"
                ;
        }

        $html_page .= "</table></td><td valign=top><table width=100%>";

        # Depends on
        $statement = "SELECT d.child, t.title FROM depends d, tasks t WHERE d.parent = ? AND d.child = t.id";
        $sth       = $dbh->prepare($statement);
        $sth->execute($tid);
        while ( my $res = $sth->fetchrow_arrayref ) {
            my ($id, $title) = @$res;
            #$html_page .= "<tr><td>$id</td><td><a href=\"$c{misc}{baseurl}forms.pl?form=deldepends&type=child&tid=$tid&relative=$id\"><img src=\"$c{misc}{baseurl}images/delete.jpg\" width=23 height=21></a></td><td><a href=\"$c{misc}{baseurl}index.pl?tid=$id\">$title</a></td></tr>\n";
            $html_page .=
                  "<tr>"
                . "<td width=10% align=right>$id</td>"
                . "<td width=5>&nbsp;</td>"
                . "<td><a href=\"$c{misc}{baseurl}index.pl?tid=$id\">$title</a></td>"
                . "<td align=right>"
                  . mk_button('Remove', "$c{misc}{baseurl}forms.pl?form=deldepends&type=child&tid=$tid&relative=$id", "Are you sure you want to remove this dependency?")
                . "</td>"
                . "</tr>\n";
        }

        $html_page .= "</table></td></tr>";

        $html_page .= "</table>";

        # dependency footer

        $html_page .= "<table width=100%><tr valign=top align=left>"
          . "<td width=50%>&nbsp;</td>"
          . "<td width=50%><form method=get action=\"$c{misc}{baseurl}forms.pl\"><input type=hidden name=form value=adddepends><input type=hidden name=type value=child><input type=hidden name=tid value=\"$tid\"><input text name=\"relative\" size=5 autocomplete=off><input type=submit value=\"Add\" style=\"background-color: #f0f0f0\"></form></td>"
          ;

        $html_page .= "</tr></table>\n\n\n";

        if (my @grandchildren = grandchildren_of($tid)) {
            $html_page .=
                "<table width=100%><tr>"
              . "<th valign=top align=left width=50%></th>"
              . "<th valign=top align=left width=50%><u>Further Dependencies</u></th></tr>"
              ;

            $html_page .= "<tr valign=top><td></td><td><table width=100%>";

            my $tasklist = join ', ', @grandchildren;
            $statement = "SELECT id, title FROM tasks WHERE id IN ($tasklist)";
            $sth       = $dbh->prepare($statement);
            $sth->execute();
            while ( my $res = $sth->fetchrow_arrayref ) {
                my ($id, $title) = @$res;
                $html_page .=
                      "<tr>"
                    . "<td width=10% align=right>$id</td>"
                    . "<td width=5>&nbsp;</td>"
                    . "<td><a href=\"$c{misc}{baseurl}index.pl?tid=$id\">$title</a></td>"
                    . "</tr>\n";
            }

            $html_page .= "</table></td></tr></table>";
        }
        
        $html_page .= "</td></tr></table>\n";

        # Attachments
        $html_page .=
            "<table width=100%><tr><td valign=top align=left>\n"
          . "<tr><td>\n"
          . "<a name=\"file\"></a>"
          . mk_title("File Attachments")
          . "</td></tr>\n"
          . "<tr><td>\n\n\n"
          ;
        $html_page .= "<table width=100%>\n";
        $html_page .=
            "<tr><th align=left width=5%>&#160;</th>"
          .     "<th align=left width=35%><u>Name</u></th>"
          .     "<th align=left width=15%><u>Type</u></th>"
          .     "<th align=left width=10%><u>Size</u></A>"
          .     "<th align=left width=20%><u>By</u></th>"
          .     "<th align=left width=15%><u>Date</u></th></tr>\n"
          ;
        $statement = "SELECT a.file_id, DATE_FORMAT(a.recorded, \"%Y-%m-%d\"), u.username, a.file_name, a.file_type, length(a.content) FROM attachments a, user u WHERE task_id = ? AND a.dev_id = u.id";
        $sth = $dbh->prepare($statement);
        $sth->execute($tid);
        while ( my $res = $sth->fetchrow_arrayref ) {
            my ($fid, $date, $dev, $filename, $type, $size) = @$res;
            $size = int($size/1024);
            $html_page .=
                "<tr><td>"
                  . mk_button('Delete', "$c{misc}{baseurl}forms.pl?form=deletefile&fid=$fid&tid=$tid", "Are you sure you want to delete attached file $filename?")
              . "</td>"
              . "<td><a href=\"$c{misc}{baseurl}download/$filename?fid=$fid\" target=_blank>$filename</a></td>"
              . "<td>$type</td>"
              . "<td>$size KB</td>"
              . "<td>$dev</td>"
              . "<td>$date</td></tr>\n"
              ;
        }
        $html_page .= 
            "</table></td></tr><tr><td>"
          . "<form method=post enctype=\"multipart/form-data\" action=\"$c{misc}{baseurl}forms.pl\">"
          . "<input type=file size=30 maxsize=255 name=filename>"
          . "<input type=hidden name=form value=attachfile>"
          . "<input type=hidden name=tid value=\"$tid\">"
          . "<input type=submit value=Attach style=\"background-color: #f0f0f0\"></form>"
          ;
        $html_page .= "\n\n\n</td></tr></table>\n";

        # High-Level Description
        if ( $cgi->param("descrip") ) {
            $descrip =~ s/^<pre>//g;
            $descrip =~ s/<\/pre>$//g;

            $html_page .=
                "<a name=\"description\"></a>\n"
              . "<table width=\"100%\">\n"
              . "<tr>\n"
              . "<td valign=top align=center>\n"
              . "<a name=\"hld\"></a>"
              . mk_title("High-Level Description")
              . "<form method=post action=\"forms.pl\">\n"
              . "<input type=hidden name=tid value=\"$tid\">\n"
              . "<input type=hidden name=form value=\"chdescrip\">\n"
              . "<textarea name=descrip wrap=hard rows=40 cols=80>$descrip</textarea>\n"
              . "</td></tr>\n"
              . "<tr><td>\n"
              . "&#160;&#160;$c{button}{ok}\n"
              . "$c{button}{cancel}\n"
              . "<p>\n"
              . "</td></tr>\n"
              ;
        }
        else {
            $descrip = hyperlink($descrip);
            $descrip =~
              s/(WL\#([0-9]+))/<a href=\"$c{misc}{baseurl}?tid=$2\">$1<\/a>/g;
            $descrip =~
              s/(BUG\#([0-9]+))/<a href=\"$c{misc}{bugsdb}$2\">$1<\/a>/g;
            $html_page .=
                "<table width=\"100%\">\n"
              . "<tr>\n"
              . "<td valign=top>\n"
              . "<a name=\"hld\"></a>"
              . mk_title("High-Level Description")
              . "<table width=600><tr><td>"
              . $descrip
              . "</td></tr></table>\n"
              . "</td></tr>\n"
              . "<tr><td align=left>\n"
              ;

            $html_page .= mk_button( "Edit High-Level Description", "index.pl?tid=$tid&descrip=1#description" );

            $html_page .= "<p></td></tr></table>\n";
        }

        # High-Level Specification
        if ( $cgi->param("hla") ) {
            $hla =~ s/^<pre>//g;
            $hla =~ s/<\/pre>$//g;

            $html_page .=
                "<a name=\"hla\"></a>\n"
              . "<table width=\"100%\">\n"
              . "<tr>\n"
              . "<td valign=top align=center>\n"
              . "<a name=\"hla\"></a>"
              . mk_title("High-Level Specification")
              . "<form method=post action=\"forms.pl\">\n"
              . "<input type=hidden name=tid value=\"$tid\">\n"
              . "<input type=hidden name=form value=\"chhla\">\n"
              . "<textarea name=hla wrap=hard rows=40 cols=80>$hla</textarea>\n"
              . "</td></tr>\n"
              . "<tr><td>\n"
              . "&#160;&#160;$c{button}{ok}\n"
              . "$c{button}{cancel}\n"
              . "<p>\n"
              . "</td></tr>\n"
              ;
        }
        else {
            $hla = hyperlink($hla);
            $hla =~
              s/(WL\#([0-9]+))/<a href=\"$c{misc}{baseurl}?tid=$2\">$1<\/a>/g;
            $hla =~
              s/(BUG\#([0-9]+))/<a href=\"$c{misc}{bugsdb}$2\">$1<\/a>/g;
            $html_page .=
                "<table width=\"100%\">\n"
              . "<tr>\n"
              . "<td valign=top>\n"
              . "<a name=\"hla\"></a>"
              . mk_title("High-Level Specification")
              . "<table width=600><tr><td>"
              . $hla
              . "</td></tr></table>\n"
              . "</td></tr>\n"
              . "<tr><td align=left>\n"
              ;

            $html_page .= mk_button( "Edit High-Level Specification", "index.pl?tid=$tid&hla=1#hla" );

            $html_page .= "<p></td></tr></table>\n";
        }

        # Low-Level Design
        if ( $cgi->param("lld") ) {
            $lld =~ s/^<pre>//g;
            $lld =~ s/<\/pre>$//g;

            $html_page .=
                "<a name=\"lld\"></a>\n"
              . "<table width=\"100%\">\n"
              . "<tr>\n"
              . "<td valign=top align=center>\n"
              . "<a name=\"lld\"></a>"
              . mk_title("Low-Level Design")
              . "<form method=post action=\"forms.pl\">\n"
              . "<input type=hidden name=tid value=\"$tid\">\n"
              . "<input type=hidden name=form value=\"chlld\">\n"
              . "<textarea name=lld wrap=hard rows=40 cols=80>$lld</textarea>\n"
              . "</td></tr>\n"
              . "<tr><td>\n"
              . "&#160;&#160;$c{button}{ok}\n"
              . "$c{button}{cancel}\n"
              . "<p>\n"
              . "</td></tr>\n"
              ;
        }
        else {
            $lld = hyperlink($lld);
            $lld =~
              s/(WL\#([0-9]+))/<a href=\"$c{misc}{baseurl}?tid=$2\">$1<\/a>/g;
            $lld =~
              s/(BUG\#([0-9]+))/<a href=\"$c{misc}{bugsdb}$2\">$1<\/a>/g;
            $html_page .=
                "<table width=\"100%\">\n"
              . "<tr>\n"
              . "<td valign=top>\n"
              . "<a name=\"lld\"></a>"
              . mk_title("Low-Level Design")
              . "<table width=600><tr><td>"
              . $lld
              . "</td></tr></table>\n"
              . "</td></tr>\n"
              . "<tr><td align=left>\n"
              ;

            $html_page .= mk_button( "Edit Low-Level Design", "index.pl?tid=$tid&lld=1#lld" );

            $html_page .= "<p></td></tr></table>\n";
        }

        # Progress Reports / Amendments
        $html_page .= "<a name=\"progress\"></a>";
        $html_page .= mk_title("Progress Reports") . "<br>";
        $html_page .= "&#160;"
          . mk_button( "Add Progress Report",
            "index.pl?tid=$tid&progrep=1#progress" )
          unless $cgi->param('progrep');
        $html_page .= "<table cellspacing=2 cellpadding=2 width=\"100%\" border=0>";

        if ( $cgi->param('progrep') ) {
            $html_page .=
                  "<tr>\n"
                . "<td valign=top colspan=2>\n"
                . "<form method=post action=\"forms.pl\">\n"
                . "<input type=\"hidden\" name=\"form\" value=\"addprogrep\">\n"
                . "<input type=\"hidden\" name=\"tid\" value=\"$tid\">\n"
                . "<textarea name=text wrap=hard rows=30 cols=100></textarea>\n"
                . "<br>\n"
                ;

            $html_page .= updatetime_html;
            
            $html_page .= 
                  "&#160;&#160;$c{button}{ok}\n"
                . "$c{button}{cancel}\n"
                . "</form>\n"
                . "<hr>\n</td></tr>\n";
        }

        $statement = "SELECT count(*) FROM amendments WHERE task_id = ? AND type = 'note'";
        $sth = $dbh->prepare($statement);
        $sth->execute($tid);

        my $count = ( $sth->fetchrow_array );

        my $limit = 'LIMIT 10';
        if ( $cgi->param('nolimit') ) {
            $limit = '';
        }

        $statement = 
          "SELECT id, dev_id, date_format(date, '%a, %d %b %Y, %H:%i'), text FROM amendments "
          . "WHERE task_id = ? AND type = 'note' ORDER BY date DESC $limit";
        $sth = $dbh->prepare($statement);
        $sth->execute($tid);
        my $c = 0;
        while ( my ( $amend_id, $devid, $date, $text ) = $sth->fetchrow_array )
        {
            $html_page .= "<tr><td colspan=2><hr></td></tr>\n" if $c++;
            my $devname = get_devname($devid);
            $devname = 'Unknown' if ( ! defined $devname || $devname eq '' );
            chomp $text;
            $date =~ s/\s/\&\#160\;/g;
            $html_page .= "<tr><td align=\"left\" valign=\"top\" colspan=2>"
              . "(<font size=\"-1\" color=$c{color}{dred}>$devname - $date</font>)&#160;</td></tr>\n"
              . "<tr><td>&#160;&#160;&#160;&#160;</td><td width=\"100%\">";
            $text = hyperlink($text);
            $text =~
              s/(WL\#([0-9]+))/<a href=\"$c{misc}{baseurl}?tid=$2\">$1<\/a>/g;
            $text =~ s/(BUG\#([0-9]+))/<a href=\"$c{misc}{bugsdb}$2\">$1<\/a>/g;

            $html_page .= $text;

            #$html_page .= link_file_html($amend_id);
            $html_page .= "</td></tr>\n";
        }

        if ( !$cgi->param('nolimit') && $count > 10 ) {
            $html_page .= "<tr><td colspan=2 align=center>-- <a href=\"$url?tid=$tid&nolimit=1\">View All Progress Notes ($count total)</a> --</td></tr>\n";
        }

        $html_page .= "</table>";
        $html_page .= page_end 'tasks';

        mark_seen $tid, get_current_id;

        print $html_page;
    }
}

########################################################################
######## Viewing virtual task

sub _view_virtual_task {
    my $virtual_task   = shift;

    if ( $virtual_task eq '' ) {
        error("$c{err}{noid} Task: $virtual_task");
    }
    else {
        my $tasks = {};
        my @tids = ();
        my @children = ();
        my $statement = '';
        my $sth = '';
        my $barwidth = 300;
        my @fields = qw( hw hr oe );
        my $title = '';

        # Build list of all member tasks of the set $virtual_task
        my ($virtual_type, $virtual_selector) = $virtual_task =~ /^(.*?):(.*)$/;
        if ($virtual_type eq 'version') {
            $title = "Version: $virtual_selector";
            $statement = "SELECT id FROM tasks WHERE version = ? AND arch = 'n' ORDER BY priority DESC";
        }
        elsif ($virtual_type eq 'category') {
            $title = "Category: $virtual_selector";
            $statement = "SELECT t.id FROM tasks t, categories c WHERE t.cat_id = c.id AND t.arch = 'n' AND c.category = ? ORDER BY t.priority DESC";
        }
        elsif ($virtual_type eq 'queue') {
            $title = "Queue $virtual_selector";
            $statement = "SELECT t.id FROM tasks t, categories c WHERE t.cat_id = c.id AND t.arch = 'n' AND c.queue = ? ORDER BY t.priority DESC";
        }
        elsif ($virtual_type eq 'status') {
            my $status = get_status $virtual_selector;
            $title = "Status: $status";
            $statement = "SELECT id FROM tasks WHERE status = ? AND arch = 'n' ORDER BY priority DESC";
        }
        elsif ($virtual_type eq 'grpldr') {
            my $username = get_devname $virtual_selector;
            $title = "Supervisor: $username";
            $statement = "SELECT id FROM tasks WHERE supervisor = ? AND arch = 'n' ORDER BY priority DESC";
        }
        elsif ($virtual_type eq 'developer') {
            my $username = get_devname $virtual_selector;
            $title = "Developer: $username";
            $statement = "SELECT id FROM tasks WHERE developer = ? AND arch = 'n' ORDER BY priority DESC";
        }
        else {
            error("Unknown virtual type in $virtual_task");
        }

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

        my $html_page   = page_start("$title");
        $html_page .= table_start( 'normal', { actions => 1, tid => $virtual_task, did => get_current_id, view => 'both' } );
        $html_page .= mk_title( "$title", 1 );

        $title =~ s/"/&quot;/g;

        # Time Estimates
        $html_page .=
            "<table width=100% border=0><tr><td valign=top align=left>\n"
            . "<tr><td>\n"
            . mk_title("Time Estimates")
            . "</td></tr>\n"
            . "<tr><td>\n\n\n"
            ;

        # -- Time Reports
        $html_page .=
            "<table width=100% border=0><tr>"
            . "<th>&nbsp;</th>"
            . "<th width=40><u>Hrs Worked</u></th>"
            . "<th width=" . ($barwidth + 10) . "><u>Progress</u></th>"
            . "<th width=40><u>Current</u></th>"
            . "<th width=40><u>Original</u></th>"
            . "</tr>\n"
            ;

        # - get hours worked and current estimate for this task
        $statement =
              "SELECT task_id, SUM(hrs_worked), SUM(estimate_delta)"
            . "  FROM timelog"
            . " WHERE task_id IN ("
            . join(',', @children, @tids) . ")"
            . " GROUP BY task_id"
            ;
        $sth = $dbh->prepare($statement);
        $sth->execute();
        while (my ($tid, $hw, $hr) = $sth->fetchrow_array) {
            my $task = $tasks->{$tid};
            $task->{'hw'} = $hw;
            $task->{'hr'} = $hr;
        }
        $sth->finish;

        # - get original estimate for this task
        for my $tid (@tids, @children) {
            my $task = $tasks->{$tid};
            my $statement =
                "SELECT estimate_delta"
                . "  FROM timelog"
                . " WHERE task_id = ?"
                . "   AND estimate_delta > 0"
                . " ORDER BY recorded"
                . " LIMIT 1"
                ;
            my $sth = $dbh->prepare($statement);
            $sth->execute($tid);
            $task->{'oe'} = $sth->fetchrow_array;
            $sth->finish;
        }

        my $subtotal          = { map { $_, 0 } @fields };
        my $subtotal_children = { map { $_, 0 } @fields };
        my $grand_total       = { map { $_, 0 } @fields };
        for my $tid (@tids) {
            my $task = $tasks->{$tid};
            my $title = get_title $tid;
            my $label = "<a href=\"$c{misc}{baseurl}index.pl?tid=$tid\">$title</a>";
            # next if $worked == 0 && $remain == 0 && $orig == 0;
            $html_page .= _view_task_template($label, $task, $barwidth, 'd');
            $subtotal->{$_} += 0 + $task->{$_}
              for (@fields);
        }
        $html_page .= _view_task_template('Sub Total', $subtotal, $barwidth, 'h');

        for my $child (@children) {
            my $task = $tasks->{$child};
            $subtotal_children->{$_} += $task->{$_}
              for (@fields);
        }
        $html_page .= _view_task_template('Sub Tasks', $subtotal_children, $barwidth, 'd');
        $grand_total->{$_} = $subtotal->{$_} + $subtotal_children->{$_}
          for (@fields);
        $html_page .= _view_task_template('Total', $grand_total, $barwidth, 'h');

        # -- close time estimates
        $html_page .=
            "</table>"
          . "</td></tr></table>\n";

        $html_page .= page_end 'tasks';

        # mark_seen $tid, get_current_id;

        print $html_page;
    }
}

sub _view_task_template {
    my ($label, $task, $width, $dh) = @_;
    my $worked = $task->{'hw'};
    my $remain = $task->{'hr'};
    my $orig   = $task->{'oe'};
    my ($pctdone, $pctremain) = percentages($worked, $remain, $width);
    $dh ||= 'd';
    return
        "<tr><t$dh align=right>$label</t$dh>"
        . "<t$dh align=right>$worked</t$dh>"
        . "<td align=center valign=middle>"
        .   "<img src=\"$c{misc}{baseurl}images/black.gif\" width=$pctdone height=10>"
        .   "<img src=\"$c{misc}{baseurl}images/silver.gif\" width=$pctremain height=10>"
        . "</td>"
        . "<t$dh align=right>$remain</t$dh>"
        . "<t$dh align=right>$orig</t$dh>"
        . "</tr>\n"
        ;

}

########################################################################
######## Viewing tasks as text

sub _view_as_text {
    if ( $cgi->param('tid') eq '' ) {
        my $catname = shift;

        $catname = ( $catname =~ m/^MASTER\-(.+)$/ ) ? "%-$1" : $catname;
        my $master = ( $cgi->param('catname') =~ m/^MASTER\-(.+)$/ ) ? 1 : 0;

        my $dvid;
        my $arch = ( $cgi->param('archtask') ) ? 'y' : 'n';
        my $show_devid = $cgi->param('show_devid');
        $show_devid =
          ( $show_devid == 0 || $show_devid eq '' ) ? '%' : $show_devid;
        my $dtest =
          ( $cgi->param('desc') eq '1' || $cgi->param('desc') eq '' ) 
          ? '1'
          : '0';
        my $desc = ($dtest) ? 'ASC' : 'DESC';
        my $limit;

        if ($master) {
            $limit = '';
        }
        else {
            my $low =
              ( $cgi->param('lim') eq '' || $cgi->param('lim') eq '0' ) 
              ? '0'
              : 15 * $cgi->param('lim') - 15;
            my $high = $low + 15;
            $limit =
              ( $cgi->param('lim') eq 'all' ) 
              ? ''
              : "LIMIT $low,$c{misc}{view_limit}";
        }

        if ( $cgi->param('sort') eq ''
            && $cgi->param('catname') =~ m/^.+\-Sprint$/ )
        {
            $dvid = "dev.username $desc, priority DESC, title";
        }
        elsif ( $cgi->param('sort') eq ''
            && $cgi->param('catname') !~ m/^.+\-Sprint$/ )
        {
            $dvid = "version $desc, priority DESC, st.status, title";
        }
        elsif ( $cgi->param('sort') eq 'prio' ) {
            $desc = ( $desc eq 'ASC' ) ? 'DESC' : 'ASC';
            $dvid = "priority $desc, st.status DESC, title";
        }
        elsif ( $cgi->param('sort') eq 'grpldr' ) {
            $desc = ( $desc eq 'ASC' ) ? 'DESC' : 'ASC';
            $dvid = "tasks.grpldr $desc, priority DESC, title";
        }
        elsif ( $cgi->param('sort') eq 'assign' ) {
            $dvid = "dev.username $desc, priority DESC, title";
        }
        elsif ( $cgi->param('sort') eq 'status' ) {
            $dvid = "st.status $desc, priority DESC, title";
        }
        elsif ( $cgi->param('sort') eq 'version' ) {
            $dvid = "version $desc";
        }
        elsif ( $cgi->param('sort') eq 'title' ) {
            $dvid = "title $desc";
        }
        elsif ( $cgi->param('sort') eq 'tid' ) {
            $dvid = "tasks.id $desc";
        }

        $dvid = ($master) ? 'cat.name, ' . $dvid : $dvid;

        my $statement =
          "SELECT DISTINCT tasks.id "
          . "FROM tasks, status st, user dev, categories cat "
          . "WHERE tasks.cat_id = cat.id AND cat.name like ? "
          . "AND tasks.arch = ? "
          . "AND st.id = tasks.status "
          . "AND tasks.developer like ? "
          . "AND dev.id = tasks.developer "
          . "ORDER BY $dvid $limit";
        my $sth = $dbh->prepare($statement);
        $sth->execute( $catname, $arch, $show_devid );

        print $cgi->header;
        print "<pre>\n";

        while ( my ($tid) = $sth->fetchrow_array ) {
            my $text = textformat_task($tid);
            $text =~ s/\</&lt;/g;
            print $text, "\n";

            #print '='x80, "\n";
        }

        if ( $c{misc}{DEBUG} ) {
            print "$statement\n";
            print "Catname: $catname\n";
            print "Arch: $arch\n";
            print "Dvid: $show_devid\n";
        }

        print "</pre>\n";
    }
    else {
        print $cgi->header;
        print "<pre>\n";

        my $text = textformat_task $cgi->param('tid');
        $text =~ s/\</&lt;/g;
        print $text, "\n";

        #print '='x80, "\n";

        print "</pre>\n";
    }

    return;
}

1;
