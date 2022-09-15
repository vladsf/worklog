#
# WorkLog/Forms.pm
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

package WorkLog::Forms;
use warnings;
no warnings 'uninitialized';
use strict;

our $VERSION = sprintf "%d.%03d", q$Revision: 1.25 $ =~ /(\d+)/g;

use WorkLog::Database;
use WorkLog::CGI;
use WorkLog qw(
    cat_has_tasks
    depends_loop
    error
    get_current_id
    get_email
    get_title
    htmlify_text
    is_admin
    is_person
    mail_developer
    mail_single
    mailformat_task
    mark_all_no
    mk_title
    notify_cat_owner
    page_end
    page_start
    personlist
    sanitize_txt_input
    show_tasks
    table_start
    updatetime_html
    wk_insert_progrep
    wk_set_updated
    wk_update_cate
    wk_update_descrip
    wk_update_hla
    wk_update_lld
    wk_update_grpldr
    wk_update_prio
    wk_update_status
    wk_update_title
    wk_update_version
);

# Exporter
    require Exporter;
    use vars qw(%EXPORT_TAGS @ISA @EXPORT_OK);
    @ISA = qw(Exporter);
    use constant FUNCTIONS => qw(
         add_depends
         arch_task
         cat_add
         cat_del
         cate_change
         cat_form
        _change_task_role
        _change_task_role_complete_date
         change_observers
         dates_change
         del_depends
         delete_form
         delete_task
         descrip_change
         hla_change
         lld_change
         dev_del
         file_attach
         file_delete
         file_download
         file_redir
         grpldr_change
         observ_addme
         observ_form
         observ_removeme
         observ_remove
         prio_change
        _prio_form
         progrep_add
         progrep_form
        _reactivate
        _reactive_form
         reassign_change
         reassign_form
         status_change
         sql_form
         task_add
         task_add_email
         task_add_email_form
         task_change
         task_copy_email
         task_copy_email_form
         task_form
         time_change
         title_change
        _updatetime_change
        _html_escape
        _verify
        _verify_num
         version_change
        _workdone
        _worknotdone
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

my $viewer = "index.pl";
my $refer  = $cgi->referer;

use WLCONFIG;
use vars qw(%c);
*c = \%WLCONFIG::conf;

########################################################################
######## Change details of a task

sub _task_change {
    my @errors  = ();
    my $changed = 0;
    my %p       = $cgi->Vars;
    my $tid     = $p{'tid'};

    if ($p{'title'} ne $p{'old_title'}) {
        &wk_update_title( $tid, $p{'title'} );
        $changed++;
    }
    if ($p{'grpldr_select'} != $p{'old_grpldr'}) {
        &wk_update_grpldr( $tid, $p{'grpldr_select'} );
        $changed++;
    }
    if ($p{'category_select'} ne $p{'old_category'}) {
        my $catname_old = $p{'old_category'};
        my $catname_new = $p{'category_select'};
        &wk_update_cate( $tid, $catname_new );
        my ($category_new, $queue_new) = $catname_new =~ /^(.*)-(.*)$/;
        my ($category_old, $queue_old) = $catname_old =~ /^(.*)-(.*)$/;
        if ($category_old ne $category_new) {
            &wk_update_version( $tid, $c{misc}{versions}{$c{misc}{default_versions}{$category_new}}[0] );
        }
        $changed++;
    }
    if ($p{'version_select'} ne $p{'old_version'}) {
        &wk_update_version( $tid, $p{'version_select'} );
        $changed++;
    }
    if ($p{'stat_select'} ne $p{'old_stat'}) {
        &wk_update_status( $tid, $p{'stat_select'} );
        $changed++;
    }
    if ($p{'prio'} ne $p{'old_prio'} ) {
        my $prio = int( $p{'prio'} );

        if ( $prio < 1 || 99 < $prio ) {
            push @errors, "Priority must be a number 1-99.";
        }
        else {
            &wk_update_prio( $tid, $prio );
            $changed++;
        }
    }

    my @fields = qw(
        designer
        designrev
        developer
        coderev1
        coderev2
        qa
        doc
    );

    foreach my $type (@fields) {
        if ($p{"old_$type"} ne $p{"new_$type"}) {
            _change_task_role($tid, $type, $p{"old_$type"}, $p{"new_$type"});
            $changed++;
        }
        if ($p{"mark_date_$type"} eq "set" && $p{"old_mark_date_$type"} eq "clear") {
            _change_task_role_complete_date($tid, $type, $p{"mark_date_$type"});
            $changed++;
        }
        elsif ($p{"mark_date_$type"} eq "" && $p{"old_mark_date_$type"} eq "set") {
            _change_task_role_complete_date($tid, $type, 'clear');
            $changed++;
        }
    }

    if ($changed) {
        &mark_all_no($tid);
        &wk_set_updated($tid);
    }
    print $cgi->redirect("$refer");
}

sub _change_task_role {
    my ($tid, $type, $oldval, $newval) = @_;
    my %field_map = (
        designer   => 'designer',
        designrev  => 'designrev',
        developer  => 'developer',
        coderev1   => 'coderev1',
        coderev2   => 'coderev2',
        qa         => 'qa',
        doc        => 'doc',
    );
    error "Bad selector type $type in &change_task_role" unless exists $field_map{$type};
    my $sql =
        "UPDATE tasks"
      . "   SET $field_map{$type} = $newval"
      . " WHERE id = $tid"
      ;
    $dbh->do($sql);

}

sub _change_task_role_complete_date {
    my ($tid, $type, $action) = @_;
    my $sql = '';
    my %field_map = (
        designrev  => 'desrev_complete_date',
        developer  => 'dev_complete_date',
        coderev1   => 'coderev1_complete_date',
        coderev2   => 'coderev2_complete_date',
        qa         => 'qa_complete_date',
        doc        => 'doc_complete_date',
    );
    error "Bad selector type $type in &change_task_role_complete_date" unless exists $field_map{$type};
    if ($action eq 'set') {
        $sql =
            "UPDATE tasks"
          . "   SET $field_map{$type} = now()"
          . " WHERE id = $tid"
          ;
    }
    else {
        $sql =
            "UPDATE tasks"
          . "   SET $field_map{$type} = NULL"
          . " WHERE id = $tid"
          ;
    }
    $dbh->do($sql);

}

########################################################################
######## Add a dependecy between tasks

sub _add_depends {

    # Inputs: type={parent,child}, relative=<task-id>, tid=<task-id>
    my $tid      = $cgi->param('tid');
    my $type     = $cgi->param('type');
    my $relative = $cgi->param('relative') || 0;
       $relative = int($relative);
    my $parent   = $type eq 'parent' ? $relative : $tid;
    my $child    = $type eq 'child'  ? $relative : $tid;

    # Make sure they actually provided a valid number
    error 'You must use a Task ID (positive integer) when adding a dependency' if $relative < 1;

    # Make sure it's an extant relative (since we don't have foreign constraints on the db)
    my $statement = "SELECT id FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($relative);
    error $c{err}{noid}, $statement unless $sth->fetch;

    # Because database constraint exceptions trigger a die (see comments below after
    # INSERT statement), we'll have to proactively check for duplicate keys
    $statement = "SELECT child FROM depends WHERE parent = ? AND child = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute($parent, $child);
    error "Sorry, $parent already depends on $child" if $sth->fetch;

    # Make sure we're not trying to depend on ourselves
    error 'A task cannot depend on itself' if $parent == $child;

    # Check for circular dependency (????)
    if ( &depends_loop( $parent, $child ) ) {
        error "Task $child depends on task $parent (eventually), which would cause a loop";
    }

    # Add dependency to database
    $statement = "INSERT INTO depends (parent, child) VALUES (?,?)";
    $sth = $dbh->prepare($statement);
    $sth->execute($parent, $child);
      # Since RaiseError is enabled and there is a __DIE__ handler installed,
      # we'll never be able to handle the duplicate key exception here when
      # someone attempts to add a dependency that alrady exists.

    # Add a note to parent and child tasks
    &wk_insert_progrep( $parent, &get_current_id, "Dependency created: $parent now depends on $child" );
    &wk_insert_progrep( $child,  &get_current_id, "Dependency created: $parent now depends on $child" );

    # Mark records as modified
    &mark_all_no($tid);
    &wk_set_updated($tid);
    &mark_all_no($relative);
    &wk_set_updated($relative);

    # Send user back to original page with a refresh
    print $cgi->redirect($refer);
}

########################################################################
######## Delete a dependecy between tasks

sub _del_depends {

    # Inputs: type={parent,child}, relative=<task-id>, tid=<task-id>
    my $tid      = $cgi->param('tid');
    my $type     = $cgi->param('type');
    my $relative = $cgi->param('relative') || 0;
       $relative = int($relative);
    my $parent   = $type eq 'parent' ? $relative : $tid;
    my $child    = $type eq 'child'  ? $relative : $tid;

    # Assuming they actually provided a valid number
    # Assuming it's an extant relative

    # Delete dependency from database
    my $statement = "DELETE FROM depends WHERE parent = ? AND child = ?";
    my       $sth = $dbh->prepare($statement);
    $sth->execute($parent, $child);

    # Add a note to parent and child tasks
    &wk_insert_progrep( $parent, &get_current_id, "Dependency deleted: $parent no longer depends on $child" );
    &wk_insert_progrep( $child,  &get_current_id, "Dependency deleted: $parent no longer depends on $child" );

    # Mark records as modified
    &mark_all_no($tid);
    &wk_set_updated($tid);
    &mark_all_no($relative);
    &wk_set_updated($relative);

    # Send user back to original page with a refresh
#DEVONLY     print STDERR "del_depends redirecting to $c{misc}{baseurl}index.pl?tid=$tid\n";
    print $cgi->redirect("$c{misc}{baseurl}index.pl?tid=$tid");
}

########################################################################
######## Attaching a file to the task

sub _file_attach {
    # $dbh->{LongReadLen}
    # $dbh->{LongTruncOk}
    my $tid = $cgi->param('tid');
    my $uid = &get_current_id;
    my $filename = $cgi->param('filename');
    my $type = $cgi->uploadInfo($filename)->{'Content-Type'} || 'text/text';
    my $fh = $cgi->upload('filename');
    local $/;
    my $data = <$fh>;
    my $statement = "INSERT INTO attachments (task_id, dev_id, file_name, file_type, content) VALUES (?, ?, ?, ?, ?)";
    my $sth = $dbh->prepare($statement);
    $sth->execute($tid, $uid, $filename, $type, $data);
    print $cgi->redirect($refer);
}

########################################################################
######## Downloading a file attached to a task

sub _file_download {
    my $fid = $cgi->param('fid');
    my $statement = "SELECT file_name, file_type, content FROM attachments WHERE file_id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($fid);
    my ($filename, $type, $data) = $sth->fetchrow_array;
    print $cgi->header($type);
    print $data;
}

########################################################################
######## Deleting a file attached to a task

sub _file_delete {
    my $fid = $cgi->param('fid');
    my $tid = $cgi->param('tid');
    my $statement = "DELETE FROM attachments WHERE file_id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute($fid);
#DEVONLY     print STDERR "file_delete redirecting to $c{misc}{baseurl}index.pl?tid=$tid\n";
    print $cgi->redirect("$c{misc}{baseurl}index.pl?tid=$tid");
}

########################################################################
######## SQL query form

sub _sql_form {
    my $query = $cgi->param('query') || '';
    my $describe = $cgi->param('describe') || '';
    my $html = '';
    my $results_title = '';
    my $sql = '';
    if ($describe) {
        $sql = 'DESCRIBE ' . $describe;
        $results_title = "Table Description: $describe";
    }
    elsif ($query =~ /\s*select\s+/i) {
        $sql = $query;
        $results_title = "Query: $sql";
    }
    # WARNING: For those that like to play with FIRE!
    # elsif ($query =~ /\s*rawsql\s+/) {
    #     ($sql) = $query =~ /\s*rawsql\s+(.*)/;
    #     $results_title "Fool lights match: $sql";
    # }
    else {
        $sql = 'SELECT ' . $query;
        $results_title = "Query: $sql";
    }

    $html .=
          page_start('WorkLog SQL')
        . table_start('minimal', { actions => 1, fund => 1 } )
        . mk_title('WorkLog SQL', 1)
        ;
    
    $html .=
          "<form method=get action=\"$c{misc}{baseurl}forms.pl\">"
        . "<input type=hidden name=form value=sql>\n"
        . "<table width=100%>\n"
        . "<tr><td colspan=2>Available tables: "
        ;
    my @tablelinks = ();
    my @tablenames = qw{
        amendments
        attachments
        categories
        depends
        observers
        priority
        status
        tasks
        timelog
        user
        visual
    };
    for my $table (@tablenames) {
        my $q = new CGI $cgi; # copy master query
        $q->param( -name  => 'describe',
                   -value => $table );
        my $url = $q->url( -relative => 1, -query => 1 );
        push @tablelinks, "<a href=\"$url\">$table</a>";
    }
    $html .= join ', ', @tablelinks;

    $html .=
          "</td></tr>\n"
        . "<tr><td valign=top>SELECT ...</td><td>"
        . "<textarea name=query rows=10 cols=80 wrap=hard>$query</textarea>"
        . "</td></tr>\n"
        ;
        
    $html .=
          "<tr><td>"
        . "<input type=submit>"
        . "</td></tr></table>\n"
        . "</form>\n"
        ;

    $html .=
          mk_title($results_title)
        . "<table width=100%>\n"
        ;

    if ($sql) {
        my $sth = $dbh->prepare($sql);
        eval {
            local $SIG{'__DIE__'};
            $sth->execute;
        };
        if ($@) {
            $html .=
                  "<tr><td colspan=2><p>Bad news. There was a problem with your query:</p></td></tr>"
                . "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;</td><td><tt><pre>$sql</pre></tt></td></tr>"
                . "<tr><td colspan=2><p>The following error was generated:</p></td></tr>"
                . "<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;</td><td><tt>$@</tt></td></tr>"
                . "\n"
                ;
        }
        elsif ($sth->rows) {
            my $colnames = $sth->{'NAME'};
            $html .= "<tr>";
            for my $name (@$colnames) {
                $html .= "<th align=left>$name</th>";
            }
            $html .= "</tr>\n";
            while (my @row = $sth->fetchrow_array) {
                $html .= "<tr>";
                for (@row) {
                    my $value = _html_escape($_);
                    $html .= "<td>$value</td>";
                }
                $html .= "</tr>\n";
            }
        }
        else {
            $html .= "<tr><td>No results</td></tr>";
        }
        $sth->finish;
    }

    $html .=
          "</table>\n"
        . page_end('none')
        ;

    print $html;
}

sub _html_escape {
    my ($text) = @_;
    # force bytes for now
    $text = pack("C*", unpack("C*", $text));
    $text =~ s/([^A-Za-z0-9\-_.!~*'()])/uc sprintf("&#%d;",ord($1))/eg;
    return $text;
}

########################################################################
######## Marking a task role as complete

sub _workdone {
    my $tid  = $cgi->param('tid') || '';
    my $role = $cgi->param('role') || '';
    my $statement = 'INSERT INTO work_tracking (task_id, assign_type, dev_id, date) VALUES (?,?,?,now())';
    my $sth = $dbh->prepare($statement);
    $sth->execute( $tid, &assign_type($role), &get_current_id() );
    print $cgi->redirect($refer);
}

########################################################################
######## Marking a task role as not complete

sub _worknotdone {
    my $tid  = $cgi->param('tid') || '';
    my $role = $cgi->param('role') || '';
    my $statement = 'DELETE FROM work_tracking WHERE task_id = ? AND assign_type = ?';
    my $sth = $dbh->prepare($statement);
    $sth->execute( $tid, &assign_type($role) );
    print $cgi->redirect($refer);
}

########################################################################
######## updatetime_change - update task time estimates

sub _updatetime_change {
    _verify qw(tid worked lastremain);
    my (
        $tid,
        $cuid,           # Current users ID
        $statement,
        $sth,
        $worked,         # Hours $cuid workedd on $tid so far
        $remain,         # Hours remaining on $tid for $cuid
        $lastremain,     # Previous number of hours recorded as remaining
        $delta,
    ) = ();

    $tid         = $cgi->param('tid');
    $worked      = $cgi->param('worked');
    $remain      = $cgi->param('remain');
    $lastremain  = $cgi->param('lastremain');
    $cuid        = &get_current_id;
    $worked      = int($worked);
    if ( !defined $remain || $remain eq '' ) {
        $delta = 0;
    }
    elsif ( $remain eq '0' || $remain + 0 > 0) {
        $delta = int($remain) - $lastremain;
    }
    else {
        error 'Time estimated remaining must be a positive integer.';
    }
    error 'Hours worked must be a positive integer.' if $worked < 0;
    if ( $delta != 0 || $worked != 0 ) {
        $statement   = 'INSERT INTO timelog (task_id, dev_id, hrs_worked, estimate_delta, recorded)'
          . '           VALUES (?, ?, ?, ?, now())'
          ;
        $sth         = $dbh->prepare($statement);
        $sth->execute( $tid, $cuid, $worked, $delta );

        # Mark task as modified
        $statement   = 'UPDATE tasks SET lastmodified = now() WHERE id = ?';
        $sth         = $sth->prepare($statement);
        $sth->execute( $tid );
    }
    print $cgi->redirect("$c{misc}{baseurl}?tid=$tid");

}

########################################################################
######## Adding a category

sub _cat_add {
    if ( &is_admin() ) {
        my $newcat = $cgi->param('newcat') || '';
        error ('No category specified') unless $newcat ne '';
        my $cat = '';
        my $queue = '';
        ($cat, $queue) = $newcat =~ /^(.*)-(RawIdeaBin|BackLog|Sprint)$/;
        unless ($queue) {
            $cat = $newcat;
            $queue = 'Other';
        }
        my $statement = "INSERT INTO categories (name, category, queue) VALUES (?,?,?)";
        my $sth       = $dbh->prepare($statement);
        $sth->execute( $newcat, $cat, $queue );

        print $cgi->redirect("$viewer");
    }
    else {
        error "<b>ACCESS DENIED</b><br><p>You do not have Admin privileges.";
    }
}

sub _cat_del {
    my $cat_id = $cgi->param('delid');

    if ( &is_admin() ) {
        if ( !&cat_has_tasks($cat_id) ) {
            my $statement = "DELETE FROM categories WHERE id = ?";
            my $sth       = $dbh->prepare($statement);
            $sth->execute( $cgi->param('delid') );

            print $cgi->redirect("$viewer");
        }
        else {
            error show_tasks($cat_id, 'cat_id');
        }
    }
    else {
        error "<b>ACCESS DENIED</b><br><p>You do not have Admin privileges.";
    }
}

sub _cat_form {
    if ( &is_admin() ) {
        my $ptitle = "Add/Remove a Queue";

        my $html_page = &page_start($ptitle);
        $html_page .= table_start( 'minimal', { actions => 0 } );
        $html_page .= &mk_title($ptitle);

        $html_page .=
            "<br>\n"
          . "<form method=\"post\" action=\"$url\">\n"
          . "<input type=\"hidden\" name=\"form\" value=\"addcat\">\n"
          . "<table>\n"
          . "<tr><th align=right>New Queue</th>\n"
          . "<td><input type=\"text\" size=20 maxlength=255 name=\"newcat\"></td></tr>\n"
          . "</table>\n"
          . "$c{button}{ok}\n"
          . "$c{button}{cancel}\n"
          . "</form>\n"
          . "<br>\n"
          . "<b>Current Queues:</b><ul>\n"
          ;

        my $sth =
          $dbh->prepare("SELECT id, name FROM categories ORDER BY name");
        $sth->execute;

        while ( my $res = $sth->fetchrow_arrayref ) {
            $html_page .= "<li>[<font size=\"-1\"><a href=\"forms.pl?form=delcat&delid=$res->[0]\">Delete</a></font>]&#160;$res->[1]\n";
        }

        $html_page .= "</ul>\n";

        $html_page .= &page_end('all');

        print $html_page;
    }
    else {
        error "<b>ACCESS DENIED</b><br><p>You do not have Admin privileges.";
    }
}

sub _dev_del {
    my $dev_id = $cgi->param('delid');

    if ( &is_admin() ) {
        if ( !&dev_owns_tasks($dev_id) ) {
            my $statement = "DELETE FROM user WHERE id = ?";
            my $sth       = $dbh->prepare($statement);
            $sth->execute($dev_id);

            $statement = "UPDATE tasks SET enteredby = owner WHERE enteredby = ?";
            $sth = $dbh->prepare($statement);
            $sth->execute($dev_id);

            print $cgi->redirect("$viewer");
        }
        else {
            error show_tasks($dev_id, 'owner');
        }
    }
    else {
        error "<b>ACCESS DENIED</b><br><p>You do not have Admin privileges.";
    }
}

########################################################################
######## Adding a task

sub _task_add {
    _verify qw(cat_id title description status priority);
    _verify_num qw(cat_id priority);
    my $statement =
      "INSERT INTO tasks (supervisor, developer, creator, owner, cat_id, title, description, "
      . "creation_date, status, priority, version) VALUES "
      . "(?,?,?,?,?,?,?,now(),?,?,?)";

    my $title       = sanitize_txt_input( $cgi->param('title') );
    my $description = sanitize_txt_input( $cgi->param('description') );

    my $sth = $dbh->prepare($statement);
    $sth->execute(
        $cgi->param('grpldr'), $cgi->param('dev_id'),
        &get_current_id(),     &get_current_id(), $cgi->param('cat_id'),
        $title,                &htmlify_text($description),
        $cgi->param('status'), $cgi->param('priority'),
        $cgi->param('version')
    );
    my $insertid = $sth->{mysql_insertid};

    foreach my $developer ( $cgi->param('observ') ) {
        $statement = "INSERT INTO observers (task_id, dev_id) VALUES (?, ?)";
        $sth = $dbh->prepare($statement);
        $sth->execute( $insertid, $developer );
    }

    $statement = 'INSERT INTO timelog (task_id, dev_id, estimate_delta, recorded) VALUES (?,?,?,now())';
    $sth = $dbh->prepare($statement);
    $sth->execute($insertid, &get_current_id, $cgi->param('dtime'));

    &mark_all_no($insertid);

    &mail_developer( mailformat_task( 'New', $insertid ) );

    &notify_cat_owner( $insertid, $cgi->param('cat_id') );

    print $cgi->redirect("$viewer");
}

sub _task_form {
    if ( &is_person() ) {
        my $ptitle = "Add a Task";
        my $statement = '';
        my $sth = '';
        my $ar_dev = '';

        my $upload_id = crypt( rand 1, rand 100 );
        my $html_page = &page_start($ptitle);
        $html_page .= table_start( 'normal', { actions => 1, fund => 1, view => 'both' } );
        $html_page .= &mk_title($ptitle);

        $html_page .=
            "<form method=\"post\" action=\"$url\">\n"
          . "<input type=\"hidden\" name=\"form\" value=\"addtask\">\n"
          . "<input type=\"hidden\" name=\"upload_id\" value=\"$upload_id\">\n"
          . "<table>\n"
          . "<tr><th align=\"right\">Task title</th>\n"
          . "<td colspan=3><input type=\"text\" name=\"title\" maxlength=255 size=\"50\"></td></tr>\n"
          ;

        $statement = "SELECT id, username FROM user ORDER BY username";
        $sth       = $dbh->prepare($statement);
        $sth->execute;
        $ar_dev = $sth->fetchall_arrayref;

        $html_page .=
            "<tr><th align=\"right\">Supervisor</th>\n"
          . "<td valign=top colspan=3><select name=\"grpldr\">\n"
          ;

        $statement = "SELECT id, username FROM user WHERE grpldr='y' ORDER BY username";
        $sth = $dbh->prepare($statement);
        $sth->execute;
        my $grpar_dev = $sth->fetchall_arrayref;
        foreach my $res ( @{$grpar_dev} ) {
            my $sel = ( $res->[1] eq 'None' ) ? " selected" : "";
            $html_page .= "<option value=\"$res->[0]\"$sel>$res->[1]</option>\n";
        }

        $html_page .=
            "</select></td></tr>\n"
          . "<tr>"
          . "<th align=\"right\" valign=top>Assigned To</th>\n"
          . "<td valign=top colspan=3><select name=\"dev_id\">\n"
          ;

        foreach my $res ( @{$ar_dev} ) {
            my $sel = ( $res->[1] eq 'Open to All' ) ? " selected" : "";
            $html_page .= "<option value=\"$res->[0]\"$sel>$res->[1]</option>\n";
        }

        $html_page .=
            "</select></td></tr>\n"
          . "<tr><th align=\"right\" valign=\"top\">Copies To</th>"
          . "<td valign=top><select name=\"observ\" size=10 multiple>\n"
          ;

        foreach my $res ( @{$ar_dev} ) {
            $html_page .= "<option value=\"$res->[0]\">$res->[1]</option>\n";
        }

        $html_page .=
            "</select></td></tr>\n"
          . "<tr><th align=\"right\">Queue</th>\n"
          . "<td colspan=3><select name=\"cat_id\">\n"
          ;
        my $catname = $cgi->param('catname');
        $html_page .= "<!-- cn: $catname -->\n";
        $statement = "SELECT id, name FROM categories ORDER BY name";
        $sth       = $dbh->prepare($statement);
        $sth->execute;
        while ( my ($cat_id, $categories_name) = $sth->fetchrow_array) {
            my $sel = ( $categories_name eq $catname ) ? " selected" : "";
            $html_page .= "<!-- $categories_name :: $catname -->\n";
            $html_page .= "<option value=\"$cat_id\"$sel>$categories_name</option>\n";
        }

        $html_page .=
            "</select></td></tr>\n"
          . "<tr><th align=\"right\">Version</th>\n"
          . "<td colspan=3><select name=\"version\">\n"
          ;

        foreach my $item ( sort keys %{ $c{misc}{versions} } ) {
            my ($category, $queue) = $catname =~ /^(.*)-(.*)$/;
            my $sel = exists $c{misc}{default_versions}{$category} ? " selected" : "";
              # ( $catname eq $c{misc}{default_versions}{$item}[0]
              # || $catname eq $c{misc}{default_versions}{$item}[1]
              # || $catname eq $c{misc}{default_versions}{$item}[2]
              # || $catname eq $c{misc}{default_versions}{$item}[3]
              # || $catname eq $c{misc}{default_versions}{$item}[4]
              # || $catname eq $c{misc}{default_versions}{$item}[5]
              # || $catname eq $c{misc}{default_versions}{$item}[6]
              # || $catname eq $c{misc}{default_versions}{$item}[7]
              # || $catname eq $c{misc}{default_versions}{$item}[8]
              # || $catname eq $c{misc}{default_versions}{$item}[9]
              # || $catname eq $c{misc}{default_versions}{$item}[10]
              # || $catname eq $c{misc}{default_versions}{$item}[11]
              # || $catname eq $c{misc}{default_versions}{$item}[12]
              # || $catname eq $c{misc}{default_versions}{$item}[13]
              # || $catname eq $c{misc}{default_versions}{$item}[14]
              # || $catname eq $c{misc}{default_versions}{$item}[15]
              # || $catname eq $c{misc}{default_versions}{$item}[16]
              # || $catname eq $c{misc}{default_versions}{$item}[17] )
            my $greatestver = ( @{ $c{misc}{versions}{$item} }[0] );
            $html_page .= "<option value=\"$item-$greatestver\"$sel>$item</option>\n";
            $html_page .= "<!-- $catname =~ $c{misc}{default_versions}{$item} -->\n";
            foreach my $itemver ( @{ $c{misc}{versions}{$item} } ) {
                $html_page .= "<option value=\"$item-$itemver\">  $itemver</option>\n";
            }
        }

        $html_page .=
            "</select></td></tr>\n"
          . "<tr><th align=right>Status</th>\n"
          . "<td colspan=3><select name=\"status\">\n"
          ;

        $statement = "SELECT id, status, `default` FROM status ORDER BY id";
        $sth       = $dbh->prepare($statement);
        $sth->execute;
        while ( my $res = $sth->fetchrow_arrayref ) {
            my $sel = ( $res->[2] eq 'y' ) ? " selected" : "";
            $html_page .= "<option value=\"$res->[0]\"$sel>$res->[1]</option>\n";
        }

        $html_page .=
            "</select></td></tr>\n"
          . "<tr><th align=\"right\">Priority</th>\n"
          . "<td colspan=3><input type=text name=\"priority\" value=\"60\" size=2 maxlength=2> <img src=\"images/prio_scale.gif\" height=15 width=200 alt=\"1-99, low-high\">\n"
          . "</td></tr>\n"
          . "<tr><th valign=top align=right>Description</th>\n"
          . "<td colspan=3><textarea name=description wrap=hard rows=20 cols=80></textarea>\n"
          . "</td></tr>\n"
          . "<tr><th align=left colspan=4>Estimated Developer Time</th></tr>\n"
          . "<tr><td valign=middle colspan=3><hr noshade align=left width=\"60%\"></td></tr>\n"
          . "<tr><th align=\"right\">Hour(s)</th>\n"
          . "<td colspan=3>\n"
          . "<input type=\"text\" name=\"dtime\" maxlength=3 size=3></td></tr>\n"
          . "<tr><td colspan=2>&#160;</td></tr>\n"
          . "</table>\n"
          . "$c{button}{ok}\n"
          . "$c{button}{cancel}\n"
          . "</form>\n"
          ;

        $html_page .= &page_end('tasks');

        print $html_page;
    }
    else {
        error "<b>ACCESS DENIED</b><br><p>You are not a valid user.";
    }
}

sub _task_add_email_form {
    if ( &is_person() ) {
        my $ptitle = "Add New Task via Email";

        my $html_page = &page_start($ptitle);
        $html_page .= table_start( 'normal', { actions => 1, fund => 1, view => 'both'} );
        $html_page .= &mk_title($ptitle);

        my $devemail = &get_email( &get_current_id() );

        $html_page .=
            "<form method=\"post\" action=\"$url\">\n"
          . "<input type=\"hidden\" name=\"form\" value=\"reqnew\">\n"
          . "<blockquote><table>\n"
          . "<tr><td valign=top>\n"
          . "<p>Email a blank form to &lt;<a href=\"mailto:$devemail->[0]\">$devemail->[0]</a>&gt; which can be returned via email\n"
          . "to create a new task?</td></tr>\n"
          . "<tr><td colspan=2>&#160;</td><td>\n"
          . "</table></blockquote>\n"
          . "$c{button}{ok}\n"
          . "$c{button}{cancel}\n"
          . "</form>\n"
          ;

        $html_page .= &page_end('tasks');

        print $html_page;

    }
    else {
        error "<b>ACCESS DENIED</b><br><p>You are not a valid user.";
    }

}

sub _task_add_email {
    if ( &is_person() ) {
        &mail_developer( &mailformat_newtask( 'Requested', &get_current_id() ) );
        print $cgi->redirect($viewer);
    }
    else {
        error "<b>ACCESS DENIED</b><br><p>You are not a valid user.";
    }
}

sub _task_copy_email_form {
    _verify qw(tid);
    my $tid = $cgi->param('tid');

    if ( &is_person() ) {
        my $ptitle = "Request Copy via Email";

        my $html_page = &page_start($ptitle);
        $html_page .= table_start( 'normal', { actions => 1, tid => $tid, did => get_current_id, view => 'both' } );
        $html_page .= &mk_title($ptitle);

        my $title    = &get_title($tid);
        my $devemail = &get_email( &get_current_id() );

        $html_page .=
            "<form method=\"post\" action=\"$url\">\n"
          . "<input type=\"hidden\" name=\"form\" value=\"reqcopy\">\n"
          . "<input type=\"hidden\" name=\"tid\" value=\"$tid\">\n"
          . "<blockquote><table>\n"
          . "<tr><th align=right>Task</th>\n"
          . "<td valign=top>$title (id: $tid)</td></tr>\n"
          . "<tr><td colspan=2>&#160;</td></tr>\n"
          . "<tr><td>&#160;</td><td valign=top>\n"
          . "<p>Email a copy of this task to &lt;<a href=\"mailto:$devemail->[0]\">$devemail->[0]</a>&gt;?</td></tr>\n"
          . "<tr><td colspan=2>&#160;</td><td>\n"
          . "</table></blockquote>\n"
          . "$c{button}{ok}\n"
          . "$c{button}{cancel}\n"
          . "</form>\n"
          ;

        $html_page .= &page_end('tasks');

        print $html_page;

    }
    else {
        error "<b>ACCESS DENIED</b><br><p>You are not a valid user.";
    }

}

sub _task_copy_email {
    my $tid = $cgi->param('tid');

    if ( &is_person() ) {
        &mail_developer( &mail_single( &mailformat_task( 'Requested', $tid ),
          &get_current_id() ) );
        print $cgi->redirect("$viewer?tid=$tid");
    }
    else {
        error "<b>ACCESS DENIED</b><br><p>You are not a valid user.";
    }
}

########################################################################
######## Re-assign a task

sub _reassign_form {
    error ('reassign_form function now obsolete. If you see this error, contact WorkLog developer.');
    _verify qw(tid);
    my $tid = $cgi->param('tid');

    my $ptitle = "Re-assign this Task";

    my $html_page = &page_start($ptitle);
    $html_page .= table_start( 'normal', { actions => 1, tid => $tid, did => get_current_id, view => 'both' } );

    my $title = &get_title($tid);

    $html_page .= &mk_title($ptitle);
    $html_page .=
        "<form method=\"post\" action=\"$url\">\n"
      . "<input type=\"hidden\" name=\"form\" value=\"reassign\">\n"
      . "<input type=\"hidden\" name=\"tid\" value=\"$tid\">\n"
      . "<table width=100%>\n"
      . "<tr><th align=right width=25%>Task</th>\n"
      . "<td width=5%>&#160;</td>\n"
      . "<td width=70%>$title (id: $tid)</td></tr>\n"
      . "<tr><th align=\"right\">Assigned by</th>\n"
      . "<td>&#160;</td>\n"
      . "<td valign=middle><select name=\"newowner\">\n"
      ;

    my $statement = "SELECT id, username FROM user ORDER BY username";
    my $sth       = $dbh->prepare($statement);
    $sth->execute;
    my $ownerid = &get_ownerid($tid);
    my $ar_dev  = $sth->fetchall_arrayref;
    foreach my $res ( @{$ar_dev} ) {
        my $sel = ( $ownerid == $res->[0] ) ? " selected" : "";
        $html_page .= "<option value=\"$res->[0]\"$sel>$res->[1]</option>\n";
    }

    $html_page .= "</select>&#160;(<font size=\"-1\">Currently</font>)</td></tr>\n";

            # This is very bad (because it's hidden down in the code)
            my %roles = (
                observers  => 'Copies to',
                design     => 'Design',
                designrev  => 'Design Review',
                developer  => 'Implementation',
                codereview => 'Code Review',
                qa         => 'QA',
            );

    foreach my $role ( qw( observers design designrev developer codereview qa) ) {
        my $currently_assigned = join( ', ', personlist( $tid, $role )) || '';
        $currently_assigned = ( $currently_assigned eq '' ) ? 'Nobody' : $currently_assigned;
        $html_page .=
            "<tr valign=top><th align=right>$roles{$role}</th>\n"
          . "<td>&#160;</td>\n"
          . "<td valign=middle><select name=\"$role\" size=10 multiple>\n"
          ;

        my $h_assigned = &get_didhash( $tid, $role );
        foreach my $res ( @{$ar_dev} ) {
            my $sel = ( $h_assigned->{ $res->[0] } ) ? ' selected' : '';
            $html_page .= "<option value=\"$res->[0]\"$sel>$res->[1]</options>\n";
        }
        $html_page .=
            "<option value=\"Nobody\">NOBODY</options>\n"
          . "</select>&#160;(<font size=\"-1\">Currently: $currently_assigned</font>)</td></tr>\n"
          . "<tr><td colspan=3><hr></td></tr>\n"
          ;
    }

    $html_page .=
        "</table>\n"
      . "$c{button}{ok}\n"
      . "$c{button}{cancel}\n"
      . "</form>\n"
      ;

    $html_page .= &page_end('tasks');

    print $html_page;
}

sub _reassign_change {
    my $tid      = $cgi->param('tid');
    my $newowner = $cgi->param('newowner');

            # This is very bad (because it's hidden down in the code)
            my %roles = (
                observers  => 'COPIES TO: ',
                design     => 'DESIGNED BY: ',
                designrev  => 'DESIGN REVIEW: ',
                developer  => 'IMPLEMENTATION: ',
                codereview => 'CODE REVIEW BY: ',
                qa         => 'Q.A. BY: ',
            );

            my @rolelist = qw(
                observers
                design
                designrev
                developer
                codereview
                qa
            );

    my $ls_old = 'OWNER: ' . &get_taskowner_name($tid) . "\n";
    foreach my $role (@rolelist) {
        $ls_old .=
            $roles{$role}
          . join( ', ', personlist( $tid, $role ))
          . "\n";
    }

    my $statement = "DELETE FROM assignments WHERE task_id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    $statement = "UPDATE tasks SET owner = ?, enteredby = ? WHERE id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute( $newowner, &get_current_id(), $tid );

    foreach my $role (@rolelist) {
        my @assigned = ();
        if ( $cgi->param($role) ne 'Nobody' ) {
            my @assignees = $cgi->param($role);
            push @assigned, @assignees;
            foreach my $person (@assigned) {
                $statement = "INSERT INTO assignments (task_id, dev_id, type) VALUES (?,?,?)";
                $sth = $dbh->prepare($statement);
                $sth->execute( $tid, $person, &assign_type($role) );
            }
        }
    }

    my $ls_new = 'OWNER: ' . &get_owner_name($newowner) . "\n";
    foreach my $role (@rolelist) {
        $ls_new .=
            $roles{$role}
          . join( ', ', personlist( $tid, $role ))
          . "\n";
    }

    &mk_diff_log( $tid, &get_current_id(), 'Re-assignment change.', $ls_old, $ls_new );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    print $cgi->redirect("$viewer?tid=$tid");
}

########################################################################
######## Adding a progress report

sub _progrep_form {
    _verify qw(tid);
    my $tid = $cgi->param('tid');

    my $ptitle = "Add a Progress Report";
    my $status;
    my $statement = "SELECT status FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);
    error $c{err}{noid}, $statement unless ($status) = $sth->fetchrow_array;

    my $upload_id = crypt( rand 1, rand 100 );
    my $html_page = &page_start($ptitle);
    $html_page .= table_start( 'normal', { actions => 1, tid => $tid, did => get_current_id, view => 'both' } );
    $html_page .= &mk_title($ptitle);

    my $title = &get_title($tid);

    $html_page .=
        "<form method=\"post\" action=\"$url\">\n"
      . "<input type=\"hidden\" name=\"form\" value=\"addprogrep\">\n"
      . "<input type=\"hidden\" name=\"tid\" value=\"$tid\">\n"
      . "<table>\n"
      . "<tr><th valign=top align=right>Task</th><td valign=top>\n"
      . "$title (id: $tid)</td></tr>\n"
      . "<tr><th valign=top align=right>Report</th><td valign=top>\n"
      . "<textarea name=text wrap=hard rows=30 cols=100></textarea>\n"
      . "<br>\n"
      ;

    $html_page .= updatetime_html;

    $html_page .=
        "</td></tr><tr><td colspan=2>&#160;</td></tr>\n"
      . "</table>\n"
      . "$c{button}{ok}\n"
      . "$c{button}{cancel}\n"
      . "</form>\n"
      ;

    $html_page .= &page_end('tasks');

    print $html_page;
}

sub _progrep_add {
    _verify qw(tid text worked lastremain);
    _verify_num qw(tid worked lastremain);

    my $tid         = $cgi->param('tid');
    my $cuid        = get_current_id;
    my $statement   = '';
    my $sth         = '';
    my $worked      = $cgi->param('worked');
    my $remain      = $cgi->param('remain');
    my $lastremain  = $cgi->param('lastremain');
    my $delta       = '';
    my $text        = $cgi->param('text');

    $worked      = int($worked);
    if ( !defined $remain || $remain eq '' ) {
        $delta = 0;
    }
    elsif ( $remain eq '0' || $remain + 0 > 0) {
        $delta = int($remain) - $lastremain;
    }
    else {
        error 'Time estimated remaining must be a positive integer.';
    }
    error 'Hours worked must be a positive integer.' if $worked < 0;
    if ( $delta != 0 || $worked != 0 ) {
        $statement   = 'INSERT INTO timelog (task_id, dev_id, hrs_worked, estimate_delta, recorded)'
          . '           VALUES (?, ?, ?, ?, now())'
          ;
        $sth         = $dbh->prepare($statement);
        $sth->execute( $tid, $cuid, $worked, $delta );
        my $estimate_change = $delta + $worked;
        my $estimate_change_text = '';
        if ($estimate_change == 0) {
            $estimate_change_text = 'unchanged';
        }
        else {
            my $sign = $estimate_change < 0;
            $estimate_change *= -1 if $sign;
            $estimate_change_text =
                  ($sign ? 'decreased':'increased')
                . " by $estimate_change hour"
                . ($estimate_change == 1 ? '':'s')
        }

        $text .= 
              "\n\n"
            . "Worked $worked hour" . ($worked == 1 ? ' ':'s ')
            . "and estimate $remain hour" . ($remain == 1 ? ' ':'s ')
            . "remain (original estimate $estimate_change_text)."
            ;
    }
    else {
        $text .= "\n\nReported zero hours worked. Estimate unchanged.";
    }
    
    wk_insert_progrep( $tid, $cuid, $text);

    mark_all_no($tid);
    wk_set_updated($tid);

    print $cgi->redirect("$viewer?tid=$tid");
}

########################################################################
######## Changing the priority

sub _prio_form {
    _verify qw(tid);
    _verify_num qw(tid);
    my $tid = $cgi->param('tid');

    my $ptitle = "Change the Priority";

    my $statement = "SELECT priority FROM tasks WHERE id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);
    my ($prio) = $sth->fetchrow_array;

    my $html_page = &page_start($ptitle);
    $html_page .= table_start( 'normal', { actions => 1, tid => $tid, did => get_current_id, view => 'both' } );
    $html_page .= &mk_title($ptitle);

    my $title = &get_title($tid);

    $prio = &priority_textualize($prio);

    $html_page .=
        "<form method=\"post\" action=\"$url\">\n"
      . "<input type=\"hidden\" name=\"form\" value=\"chprio\">\n"
      . "<input type=\"hidden\" name=\"tid\" value=\"$tid\">\n"
      . "<table>\n"
      . "<tr><th align=\"right\">Task</th><td>$title (id: $tid)</td></tr>\n"
      . "<tr><th align=\"right\">Priority</th>\n"
      . "<td><select name=\"prio\">\n"
      ;

    $statement = "SELECT conv, priority FROM priority ORDER BY id";
    $sth       = $dbh->prepare($statement);
    $sth->execute;
    while ( my $res = $sth->fetchrow_arrayref ) {
        my $sel = ( $res->[1] eq $prio ) ? " selected" : "";
        $html_page .= "<option value=\"$res->[0]\"$sel>$res->[1]</option>\n";
    }

    $html_page .=
        "</select></td></tr>\n"
      . "</table><p>\n"
      . "$c{button}{ok}\n"
      . "$c{button}{cancel}\n"
      . "</form>\n"
      ;

    $html_page .= &page_end('tasks');
    print $html_page;
}

sub _grpldr_change {
    my $tid    = $cgi->param('tid');
    my $grpldr = $cgi->param('grpldr');

    &wk_update_grpldr( $tid, $grpldr );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    if ( $cgi->param('list') eq '1' ) {
        print $cgi->header('text/html','204 No response');
    }
    else {
        print $cgi->redirect("index.pl?tid=$tid");
    }
}

sub _version_change {
    my $tid     = $cgi->param('tid');
    my $version = $cgi->param('version');

    &wk_update_version( $tid, $version );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    if ( $cgi->param('list') eq '1' ) {
        print $cgi->header('text/html','204 No response');
    }
    else {
        print $cgi->redirect("index.pl?tid=$tid");
    }
}

sub _status_change {
    my $tid    = $cgi->param('tid');
    my $status = $cgi->param('status');

    &wk_update_status( $tid, $status );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    if ( $cgi->param('list') eq '1' ) {
        print $cgi->header('text/html','204 No response');
    }
    else {
        print $cgi->redirect("index.pl?tid=$tid");
    }
}

sub _cate_change {
    my $tid  = $cgi->param('tid');
    my $cate = $cgi->param('cate');

    &wk_update_cate( $tid, $cate );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    if ( $cgi->param('list') eq '1' ) {
        print $cgi->header('text/html','204 No response');
    }
    else {
        print $cgi->redirect("index.pl?tid=$tid");
    }
}

sub _dates_change {
    my $tid   = $cgi->param('tid');
    my $dopti = $cgi->param('dopti');
    my $dreal = $cgi->param('dreal');
    my $dabso = $cgi->param('dabso');

    if ( $dopti !~ m/^[0-9]{4}\-[0-9]{2}\-[0-9]{2}$/
        || $dreal !~ m/^[0-9]{4}\-[0-9]{2}\-[0-9]{2}$/
        || $dabso !~ m/^[0-9]{4}\-[0-9]{2}\-[0-9]{2}$/ )
    {
        error "Date format must be YYYY-MM-DD (all numbers of course).";
    }

    &wk_update_dates( $tid, $dopti, $dreal, $dabso );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    print $cgi->redirect("$refer");
}

sub _time_change {
    my $tid  = $cgi->param('tid');
    my $time = $cgi->param('time');

    if ( $time !~ m/[0-9]{1,3}/ ) {
        error "Estimated Time Remaining must be a number 0-999.";
    }

    &wk_update_time( $tid, $time );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    print $cgi->redirect("$refer");
}

sub _descrip_change {
    my $tid     = $cgi->param('tid');
    my $descrip = $cgi->param('descrip');

    &wk_update_descrip( $tid, $descrip );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    print $cgi->redirect("index.pl?tid=$tid");
}

sub _hla_change {
    my $tid     = $cgi->param('tid');
    my $hla = $cgi->param('hla');

    wk_update_hla( $tid, $hla );

    mark_all_no($tid);

    wk_set_updated($tid);

    print $cgi->redirect("index.pl?tid=$tid");
}

sub _lld_change {
    my $tid     = $cgi->param('tid');
    my $lld = $cgi->param('lld');

    wk_update_lld( $tid, $lld );

    mark_all_no($tid);

    wk_set_updated($tid);

    print $cgi->redirect("index.pl?tid=$tid");
}

sub _title_change {
    my $tid   = $cgi->param('tid');
    my $title = $cgi->param('title');

    &wk_update_title( $tid, $title );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    print $cgi->redirect("$refer");
}

sub _prio_change {
    my $tid  = $cgi->param('tid');
    my $prio = $cgi->param('prio');
    my $old_prio = $cgi->param('old_prio');

    if ( $prio != $old_prio ) {
        $prio = int($prio);
        if ( $prio < 1 || 99 < $prio ) {
            &error("Priority must be a number 1-99.");
        }
        &wk_update_prio( $tid, $prio );
        &mark_all_no($tid);
        &wk_set_updated($tid);
    }
    print $cgi->header('text/html','204 No response');
}

########################################################################
######## Re-Activate a Task

sub _reactive_form {
    my $tid = $cgi->param('tid');

    my $ptitle = "Re-Activate this Task";
    my $view   = ( &is_arch_ready($tid) ) ? 'archived' : 'active';

    my $upload_id = crypt( rand 1, rand 100 );
    my $html_page = &page_start($ptitle);
    $html_page .= table_start( 'normal', { actions => 1, tid => $tid, did => get_current_id, view => 'both', vflag => $view } );
    $html_page .= &mk_title($ptitle);

    my $title = &get_title($tid);
    my $prio  = &get_prio($tid);
    $prio = &priority_textualize($prio);

    $html_page .=
        "<form method=\"post\" action=\"$url\">\n"
      . "<input type=\"hidden\" name=\"form\" value=\"reactivate\">\n"
      . "<input type=\"hidden\" name=\"tid\" value=\"$tid\">\n"
      . "<table>\n"
      . "<tr><th valign=top align=right>Task</th><td valign=top>\n"
      . "$title</td></tr>\n"
      . "<tr><th valign=top align=right>Report</th><td valign=top>\n"
      . "<textarea name=text wrap=hard rows=20 cols=80>Re-Activated.</textarea>\n"
      . "</td></tr>\n"
      . "<tr><td>&#160;</td><td>\n"
      . "</td></tr>\n"
      . "</table>\n"
      . "$c{button}{ok}\n"
      . "$c{button}{cancel}\n"
      . "</form>\n"
      ;

    $html_page .= &page_end('tasks');

    print $html_page;
}

sub _reactivate {
    my $tid = $cgi->param('tid');

    &wk_insert_progrep( $tid, &get_current_id(), $cgi->param('text') );

    my $statement = "UPDATE tasks SET status = ?, complete_date = ?, "
      . "arch = ? WHERE id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute( $c{misc}{strtstat}, '0', 'n', $tid );

    &mark_all_no($tid);

    &wk_set_updated($tid);

    print $cgi->redirect("$viewer?tid=$tid");
}

########################################################################
######## Delete a task

sub _delete_form {
    my $tid = $cgi->param('tid');

    my $ptitle = "Delete this Task";

    my $html_page = &page_start($ptitle);
    $html_page .= table_start( 'normal', { actions => 1, tid => $tid, did => get_current_id, view => 'both' } );
    $html_page .= &mk_title($ptitle);

    my $title = &get_title($tid);

    $html_page .=
        "<form method=\"post\" action=\"$url\">\n"
      . "<input type=\"hidden\" name=\"form\" value=\"realdelete\">\n"
      . "<input type=\"hidden\" name=\"tid\" value=\"$tid\">\n"
      . "<blockquote><table>\n"
      . "<tr><th valign=top align=right>Task</th><td valign=top>\n"
      . "$title (id: $tid)</td></tr>\n"
      . "<tr><td colspan=2>&#160;</td></tr>\n"
      . "<tr><td>&#160;</td>\n"
      . "<td valign=top>\n"
      . "<p>Are you sure you want to <b>Delete</b> this task?</td></tr>\n"
      . "<tr><td colspan=2>&#160;</td><td>\n"
      . "</table></blockquote>\n"
      . "$c{button}{ok}\n"
      . "$c{button}{cancel}\n"
      . "</form>\n"
      ;

    $html_page .= &page_end('tasks');

    print $html_page;
}

sub _delete_task {
    my $tid = $cgi->param('tid');

    # delete everything related to this task_id, except entries in 'files'
    # keep these entries to save filename <-> repos_key lookup.

    my $statement = "DELETE FROM visual WHERE task_id = ?";
    my $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    $statement = "DELETE FROM amendments WHERE task_id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    $statement = "DELETE FROM observers WHERE task_id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    $statement = "DELETE FROM tasks WHERE id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    $statement = "SELECT id FROM files WHERE task_id = ?";
    $sth       = $dbh->prepare($statement);
    $sth->execute($tid);

    while ( my ($id) = $sth->fetchrow_array ) {
        my $statement2 = "DELETE FROM file_lut WHERE file_id = ?";
        my $sth2       = $dbh->prepare($statement2);
        $sth2->execute($id);
    }

    print $cgi->redirect("index.pl");
}

########################################################################
######## Observe a task

sub _observ_form {
    my $tid = $cgi->param('tid');

    if ( &is_person() ) {
        my $task_title = get_title $tid;
        my $ptitle = "Observers for $tid ($task_title)";
        my %assigned;
        my %id;
        my %username;
        my @names;
        my $html_page = &page_start($ptitle);
        $html_page .= table_start( 'normal', { actions => 1, tid => $tid, did => get_current_id, view => 'both' } );
        $html_page .= &mk_title($ptitle);

        my $statement = "SELECT dev_id FROM observers WHERE task_id = ?";
        my $sth = $dbh->prepare($statement);
        $sth->execute($tid);
        while (my ($id) = $sth->fetchrow_array) {
            $assigned{$id} = 1;
        }

        $statement =
              "SELECT id, username"
            . "  FROM user"
            . " WHERE active = 'y'"
            ;
        $sth = $dbh->prepare($statement);
        $sth->execute;
        while (my ($id, $name) = $sth->fetchrow_array) {
            next if $name eq 'None';
            $id{$name} = $id;
            $username{$id} = $name;
        }

        @names = sort values %username;
        my $namecount = @names;
        my $columns = 4;
        my $rows = int($namecount / $columns);
        $rows++ if $namecount % $columns;

        $html_page .=
              "<form method=post action=\"$url\">\n"
            . "<input type=\"hidden\" name=\"form\" value=\"changeobservers\">"
            . "<input type=\"hidden\" name=\"tid\" value=\"$tid\">"
            . "<table width=100% border=0>";
        for my $row (1..$rows) {
            $html_page .= "<tr>";
            for my $column (0..$columns-1) {
                my $checked = '';
                my $cell = $column * $rows + $row - 1;
                my $id = $id{$names[$cell]};
                next unless defined $names[$cell];
                $checked = 'checked' if exists $assigned{$id};
                $html_page .= "<td>";
                $html_page .= "<input type=\"checkbox\" name=\"newobservers\" value=\"$id\" $checked>";
                $html_page .= "<strong>" if $checked;
                $html_page .= $names[$cell];
                $html_page .= "</strong>" if $checked;
                $html_page .= "</td>";
            }
            $html_page .= "</tr>\n";
            unless ($row % 10) {
                $html_page .=
                      "<tr><td colspan=\"$columns\">"
                    . "<input type=reset value=\"Reset All\">"
                    . "<input type=submit value=\"Submit All Changes\">"
                    . "</td></tr>"
                    ;
            }
        }
        $html_page .=
              "</table>\n"
            . "<input type=reset value=\"Reset All\">"
            . "<input type=submit value=\"Submit All Changes\">"
            . "</form>";

        $html_page .= &page_end('tasks');

        print $html_page;
    }
    else {
        &error("<b>ACCESS DENIED</b><br><p>You are not a valid user.");
    }
}

sub _change_observers {
    _verify qw(tid);
    _verify_num qw(tid);
    if ( &is_person() ) {
        my $tid = $cgi->param('tid');
        my @observers = $cgi->param('newobservers');
        $dbh->do("DELETE FROM observers WHERE task_id = $tid");
        my $statement = 
              "INSERT INTO observers (task_id, dev_id)"
            . "  VALUES (?,?)"
            ;
        my $sth = $dbh->prepare($statement);
        $sth->execute($tid, $_) for (@observers);
        &mail_developer( &mailformat_task( 'Updated', $tid ) );
        print $cgi->redirect( "$viewer?tid=" . $tid );
    }
    else {
        &error("<b>ACCESS DENIED</b><br><p>You are not a valid user.");
    }
}

sub _observ_addme {
    _verify qw(addme);
    _verify_num qw(addme);

    if ( &is_person() ) {
        my $statement =
          "SELECT dev_id FROM observers WHERE task_id = ? AND dev_id = ?";
        my $sth = $dbh->prepare($statement);
        $sth->execute( $cgi->param('addme'), &get_current_id() );

        if ( !$sth->fetchrow_array ) {
            $statement = "INSERT INTO observers (task_id, dev_id) VALUES (?,?)";
            $sth       = $dbh->prepare($statement);
            $sth->execute( $cgi->param('addme'), &get_current_id() );
        }

        &mail_developer( &mailformat_task( 'Updated', $cgi->param('addme') ) );

        print $cgi->redirect( "$viewer?tid=" . $cgi->param('addme') );
    }
    else {
        &error("<b>ACCESS DENIED</b><br><p>You are not a valid user.");
    }
}

sub _observ_removeme {
    _verify qw(removeme);
    _verify_num qw(removeme);

    if ( &is_person() ) {
        _observ_remove( $cgi->param('removeme'), &get_current_id() );
        print $cgi->redirect( "$viewer?tid=" . $cgi->param('removeme') );
    }
    else {
        &error("<b>ACCESS DENIED</b><br><p>You are not a valid user.");
    }
}

sub _observ_remove {
    my ($task_id, $dev_id) = @_;
    my $statement = "DELETE FROM observers WHERE task_id = ? AND dev_id = ?";
    my $sth = $dbh->prepare($statement);
    $sth->execute( $task_id, $dev_id );
}

########################################################################
######## File view controller

sub _file_redir {
    my $fid = $cgi->param('fid');
    my $did = &get_current_id();
    my $tid = &find_tid($fid);

    &feed_me( &get_fname($fid), &get_key($fid) );

    return;
}

########################################################################
######## Archiving a task

sub _arch_task {
    _verify qw(tid);
    _verify_num qw(tid);
    $dbh->do( "UPDATE tasks SET arch = 'y' WHERE id = " . $cgi->param('tid') );
    print $cgi->redirect("$viewer");
}

######## Miscallaneous routines

sub _verify {
    foreach (@_) {
        &error( "You didn't supply the '$_' Parameter, i.e. you didn't "
            . "fill out all the fields in the form. Please click the "
            . "Back button in your browser and check that the form "
            . "is filled." )
          unless ( $cgi->param($_) ne '' );
    }
}

sub _verify_num {
    foreach (@_) {
        &error("Parameter '$_' of wrong format (should be a number).")
          unless DBI::looks_like_number( $cgi->param($_) );
    }
}

1;
