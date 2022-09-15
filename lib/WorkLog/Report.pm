#
# WorkLog/Report.pm
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

package WorkLog::Report;
use warnings;
no warnings 'uninitialized';
use strict;

our $VERSION = sprintf "%d.%03d", q$Revision: 1.12 $ =~ /(\d+)/g;

use Data::Dumper;
use WorkLog::Database;
use WorkLog::CGI;
use WorkLog qw(
    mk_title
    page_end
    page_start
    table_start
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
    my %sort_cache = ();   # storage for sort subs in task_sorter

    my %usernames  = ();   # dev_id      => user_name
    my %ids        = ();
    my %status     = ();   # status_id   => status_name
    my @queues     = ();
    my @categories = ();
    my @versions   = ();

    my $childof    = {};   # hashref->{parent_task_id} = [ child_task_id, ...]
    my $parentof   = {};   # hashref->{child_task_id}  = [ parent_task_id, ...]

    my $columnre   = '';
    my %fields     = (
    #   Code        Title                   Type        Break   Total   F-where F-type      Field
        id  =>  [   'Task ID',              'number',   '0',    '0',    'sql',  'range',    't.id'],
        t   =>  [   'Title',                'string',   '0',    '0',    'sql',  'string',   't.title'],
        c   =>  [   'Category',             'enum',     '1',    '0',    'sql',  'list',     'c.category'],
        q   =>  [   'Queue',                'enum',     '1',    '0',    'sql',  'list',     'c.queue'],
        v   =>  [   'Version',              'enum',     '1',    '0',    'sql',  'list',     't.version'],
        s   =>  [   'Status',               'enum',     '1',    '0',    'sql',  'list',     't.status'],
        p   =>  [   'Priority',             'number',   '0',    '0',    'sql',  'range',    't.priority'],
        hw  =>  [   'Hours Worked',         'number',   '0',    '1',    'array','range',    'SUM(tl.hrs_worked)'],
        hr  =>  [   'Hours Remaining',      'number',   '0',    '1',    'array','range',    'SUM(tl.estimate_delta)'],
        phw =>  [   'Project Hours Worked', 'number',   '0',    '1',    'array','range',    ''],
        phr =>  [   'Project Hours Remain', 'number',   '0',    '1',    'array','range',    ''],
        cr  =>  [   'Creator',              'person',   '1',    '0',    'sql',  'list',     't.creator'],
        su  =>  [   'Supervisor',           'person',   '1',    '0',    'sql',  'list',     't.supervisor'],
        la  =>  [   'Lead Architect',       'person',   '1',    '0',    'sql',  'list',     't.designer'],
        ar  =>  [   'Architectural Review', 'person',   '1',    '0',    'sql',  'list',     't.designrev'],
        im  =>  [   'Implementor',          'person',   '1',    '0',    'sql',  'list',     't.developer'],
        r1  =>  [   '1st Code Review',      'person',   '1',    '0',    'sql',  'list',     't.coderev1'],
        r2  =>  [   '2nd Code Review',      'person',   '1',    '0',    'sql',  'list',     't.coderev2'],
        qa  =>  [   'QA',                   'person',   '1',    '0',    'sql',  'list',     't.qa'],
        dcr =>  [   'Date Created',         'date',     '0',    '0',    'sql',  'range',    't.creation_date'],
        dco =>  [   'Date Completed',       'date',     '0',    '0',    'sql',  'range',    't.complete_date'],
        dar =>  [   'Architecture Approved','date',     '0',    '0',    'sql',  'range',    't.desrev_complete_date'],
        dim =>  [   'Implementation Completed','date',  '0',    '0',    'sql',  'range',    't.dev_complete_date'],
        dr1 =>  [   '1st Code Review Approved','date',  '0',    '0',    'sql',  'range',    't.coderev1_complete_date'],
        dr2 =>  [   '2nd Code Review Approved','date',  '0',    '0',    'sql',  'range',    't.coderev2_complete_date'],
        dqa =>  [   'QA Approved',          'date',     '0',    '0',    'sql',  'range',    't.qa_complete_date'],
    );

use subs qw{
    all_descendants
    build_where_clause
    childof
    ellipses
    get_tasks
    import
    initialize
    generate_html
    html_tally
    parentof
    parse_options
    prepare
    pretty_date
    print
    status
    task_sorter
    username
    validate_breaks
    validate_fields
    validate_filters
    validate_orders
};

######## Public Subroutines

sub print {
    print get_tasks(parse_options($cgi));
}

######## Private

sub all_descendants {
    my ($parent) = @_;
    my @stack = ();
    my %seen  = ();
    push @stack, childof($parent);
    while (@stack) {
        my $next = pop @stack;
        $seen{$next}++;
        push @stack, childof($next);
    }
    return keys %seen;
}

sub ellipses {
    my ($text, $limit) = @_;
    $limit |= 25;
    return $text if length $text <= $limit;
    return substr($text, 0, $limit) . "...";
}

sub task_sorter {
    my ($tasks, @order) = @_;
    my $order = join '-', @order;
    return &{$sort_cache{$order}}($tasks) if exists $sort_cache{$order};

    my @sort_blocks = ();
    foreach my $column (@order) {

        # UPPERCASE column codes indicate descending order
        my ($alpha, $beta) = ('a', 'b');
           ($alpha, $beta) = ('b', 'a') if $column =~ /[A-Z]/;
        my $c = lc $column;

        push @sort_blocks, "          \$t->{\$$alpha}->{\"$c\"}   <=>            \$t->{\$$beta}->{\"$c\"}"     if $fields{$c}->{'type'} eq 'number';
        push @sort_blocks, "&username(\$t->{\$$alpha}->{\"$c\"})  cmp  &username(\$t->{\$$beta}->{\"$c\"})"    if $fields{$c}->{'type'} eq 'person';
        push @sort_blocks, "          \$t->{\$$alpha}->{\"$c\"}   cmp            \$t->{\$$beta}->{\"$c\"}"     if $fields{$c}->{'type'} eq 'enum';
        push @sort_blocks, "          \$t->{\$$alpha}->{\"$c\"}   cmp            \$t->{\$$beta}->{\"$c\"}"     if $fields{$c}->{'type'} eq 'string';
        push @sort_blocks, "          \$t->{\$$alpha}->{\"$c\"}   cmp            \$t->{\$$beta}->{\"$c\"}"     if $fields{$c}->{'type'} eq 'date';
    }
    $sort_cache{$order} = eval "sub {my (\$t)=\@_; return " . join(" || ", @sort_blocks) . ";}"; die "$@" if $@;
    return &{$sort_cache{$order}}($tasks);
}

sub username {
    my ($id) = @_;
    return $usernames{$id};
}

sub validate_breaks {
    my @fields = @_;
    foreach my $field (@fields) {
        die "Can't break on $field (" . $fields{$field}->{'title'} . ")"
            unless $fields{$field}->{'break'};
    }
}

sub validate_fields {
    my @fields = @_;
    foreach my $field (@fields) {
        die "Bad selector field [$field]" unless $field =~ /^$columnre/;
    }
    return 1;
}

sub validate_filters {
    my @fields = @_;
    foreach my $field (@fields) {
        die "Bad selector field [$field]" unless $field =~ /^$columnre[-+=]?/;
        my ($field_name, $operator, $argument) = $field =~ 
            m/^
            ($columnre)        # field_name
            (?:
                ([-+=])        # operator
                (.+)           # argument
            )
            +$/x;
        die "Unable to locate field code in $field" unless defined $field_name;
        die "Missing operator in filter code $field" unless defined $operator;
        die "Missing argument in filter code $field" unless defined $argument;
        my ($low, $high) = ();
        ($low, $high) = /(.*)\.\.(.*)/ if $argument =~ /\.\./;

        # There's other clever stuff that can be done here to idiot-proof
        # the filters, but I'm hoping to encourage not-idiots to use this first

    }
    return 1;
}

sub validate_orders {
    return 1;
    my @fields = @_;
    foreach my $field (@fields) { }
}

sub parse_options {
    my ($q) = @_;
    my @display = split /,/, ($q->param('display') || 'c,q,t,im,v,p,su,s');
    my @order   = split /,/, ($q->param('order')   || 'c,q,p');
    my @break   = split /,/, $q->param('break');
    (my $filter = $q->param('filter')) =~ s/ /+/g;
    my @filter  = split /,/, $filter;
    validate_fields(@display, @order);
    validate_filters(@filter);
    validate_breaks(@break);
    validate_orders(@order);
    return \@display, \@order, \@break, \@filter;
}

sub build_where_clause {
    my @filter = @_;
    my @wheres = ();
    my $where = '';
    foreach my $field (@filter) {
        last;
        my ($field_code, $operator, $argument) = $field =~ 
            m/^
            ($columnre)        # field_code
            (?:
                ([-+=])        # operator
                (.+)           # argument
            )
            +$/x;
        $field_code = lc $field_code;
        my $f      = $fields{$field_code};
        my $ftype  = $f->{'ftype'};
        my $column = $f->{'field'};
        my ($low, $high, @args) = ();
        ($low, $high) = $argument =~ /(.*)\.\.(.*)/ if $ftype eq 'range';
        push @args, $dbh->quote($_) foreach split /\s*\|\s*/, $argument;
        if ($ftype eq 'string') {
            push @wheres, $column . ' LIKE ' . $dbh->quote("\%$argument%");
        }
        elsif ($ftype eq 'list') {
            if (@args > 1) {
                push @wheres, $column . ' IN (' . join(',', @args) . ')';
            }
            else {
                push @wheres, $column . ' = ' . $args[0]; # already quoted
            }
        }
        elsif ($ftype eq 'range') {
            if ($low && $high) {
                push @wheres, "$column BETWEEN $low AND $high";
            }
            elsif ($operator eq '+') {
                push @wheres, "$column > $argument";
            }
            elsif ($operator eq '-') {
                push @wheres, "$column < $argument";
            }
        }
    }
    my $im          = $cgi->param('im')             || '';
    my $status      = $cgi->param('status')         || 'Assigned';
    my $queue       = $cgi->param('queue')          || 'Sprint';
    my $category    = $cgi->param('category')       || '';
    my $version     = $cgi->param('version')        || '';
    my $priority    = $cgi->param('priority')       || '';
    my $supervisor  = $cgi->param('supervisor')     || '';
    my $within      = $cgi->param('within')         || '';
    $within         = $within > 0 ? $within : 0;
    my $lastmodified = $cgi->param('lastmodified')  || 'gt';
    my $archived     = $cgi->param('archived')      || 'n';

    push @wheres, " t.developer = " . $dbh->quote($im)                          if $im          && $im ne 'Any';
    push @wheres, " t.status = status.id AND status.status = " . $dbh->quote($status)   if $status      && $status ne 'Any';
    push @wheres, " t.cat_id = c.id AND c.queue = " . $dbh->quote($queue)       if $queue       && $queue ne 'Any';
    push @wheres, " t.cat_id = c.id AND c.category = " . $dbh->quote($category) if $category    && $category ne 'Any';
    push @wheres, " t.version = " . $dbh->quote($version)                       if $version     && $version ne 'Any';
    push @wheres, " t.priority = " . $dbh->quote($priority)                     if $priority    && $priority ne 'Any';
    push @wheres, " t.supervisor = " . $dbh->quote($supervisor)                 if $supervisor  && $supervisor ne 'Any';
    push @wheres, " t.lastmodified <  SUBDATE(NOW(), INTERVAL $within DAY)"     if $within      && $lastmodified eq 'gt';
    push @wheres, " t.lastmodified >= SUBDATE(NOW(), INTERVAL $within DAY)"     if $within      && $lastmodified eq 'lte';
    push @wheres, " t.arch = 'y'"                                               if $archived eq 'y';
    push @wheres, " t.arch = 'n'"                                               if $archived eq 'n';
    if (@wheres) {
        $where = " AND " . join(" AND ", @wheres) . " ";
    }
    return $where;
}

sub get_tasks {
    my ($display, $sort_order, $break, $filter) = @_;
    # Options:
    #   display = which fields to display in the output
    #   order   = what order to sort the fields by
    #   break   = which columns to break and subtotal on
    #   filter  = limit result to certain criteria
    my ($sql, $sth, $html, %tasks) = ();
    my $dfmt = $dbh->quote('%Y%m%d %T');

    my $where = build_where_clause(@$filter);

    # This is the list of fields (as SELECT'd) that will be returned
    #   We get all the data even if we're not going to display it or 
    #   use it in any way. The phw & phr fields will be added later.
    my @select_columns = qw(
        id t c q v s p hw hr cr su la ar im r1 r2 qa
        dcr dco dar dim dr1 dr2 dqa
    );
    $sql = 
          "SELECT"
        . "       t.id,"
        . "       t.title,"
        . "       c.category,"
        . "       c.queue,"
        . "       t.version,"
        . "       t.status,"
        . "       t.priority,"
        . "       SUM(tl.hrs_worked),"
        . "       SUM(tl.estimate_delta),"
        . "       t.creator,"
        . "       t.supervisor,"
        . "       t.designer,"
        . "       t.designrev,"
        . "       t.developer,"
        . "       t.coderev1,"
        . "       t.coderev2,"
        . "       t.qa,"
        . "       DATE_FORMAT(t.creation_date,$dfmt),"
        . "       DATE_FORMAT(t.complete_date,$dfmt),"
        . "       DATE_FORMAT(t.desrev_complete_date,$dfmt),"
        . "       DATE_FORMAT(t.dev_complete_date,$dfmt),"
        . "       DATE_FORMAT(t.coderev1_complete_date,$dfmt),"
        . "       DATE_FORMAT(t.coderev2_complete_date,$dfmt),"
        . "       DATE_FORMAT(t.qa_complete_date,$dfmt)"
        . "  FROM tasks t, categories c, timelog tl, status"
        . " WHERE t.cat_id = c.id"
        . "   AND t.id = tl.task_id"
        . $where
        . " GROUP BY tl.task_id"
        ;

    $sth = $dbh->prepare($sql);
    $sth->execute;
    while (my @row = $sth->fetchrow_array) {
        my $task_id = $row[0];
        $tasks{$task_id} = { map { $select_columns[$_] => $row[$_] } 0..(@row-1) };
    }
    $sth->finish;

    # Calculate project time totals
    foreach my $task_id (keys %tasks) {
        my $hw_subtotal = 0;
        my $hr_subtotal = 0;
        foreach my $descendant (all_descendants($task_id)) {
            $hw_subtotal += $tasks{$descendant}->{'hw'};
            $hr_subtotal += $tasks{$descendant}->{'hr'};
        }
        $tasks{$task_id}->{'phw'} = $hw_subtotal;
        $tasks{$task_id}->{'phr'} = $hr_subtotal;
    }

    # Create column titles
    my $titles = [];
    my $q = $cgi->new;
    foreach my $column (@$display) {
        $q->param(-name => 'order', -value => $column);
        push @$titles, "<a href=\"" . $q->url( -relative => 1, -path => 1, -query => 1) . "\">" . $fields{$column}->{'title'} . "</a>";
    }

    my $rows = [];
    my $previous_task_id = '';
    my $break_tally      = {};
    foreach my $task_id ( sort {task_sorter(\%tasks, @$sort_order)} keys %tasks ) {
        my $break_level = 0;
        foreach my $break_field (@$break) {
            last unless $previous_task_id;
            $break_level++;
            my $this = $tasks{$task_id};
            my $last = $tasks{$previous_task_id};
            if (cmp_task_column($break_field, $this, $last)) {
                push @$rows, [ "BREAK", $break_field, $break_level, $break_tally ];
                $break_tally = {};
            }
        }
        my @columns = ();
        foreach my $column (@$display) {
            if ($fields{$column}->{'type'} eq 'person') {
                my $arg = '';
                my %somelookup = (
                    su   => 'supervisor',
                    im   => 'im',
                );
                $arg = $somelookup{$column};
                push @columns, "<a href=\"?$arg=$tasks{$task_id}->{$column}&status=Any&queue=Any\">" . username($tasks{$task_id}->{$column}) . "</a>";
            }
            elsif ($fields{$column}->{'type'} eq 'date') {
                push @columns, pretty_date($tasks{$task_id}->{$column});
            }
            elsif ($column eq 's') {
                push @columns, "<a href=\"?status=" . status($tasks{$task_id}->{$column}) . "&queue=Any\">" . status($tasks{$task_id}->{$column}) . "</a>";
            }
            elsif ($column eq 't') {
                push @columns, "<a href=\"$c{baseurl}index.pl?tid=$task_id\">" . ellipses($tasks{$task_id}->{$column}) . "</a>";
            }
            elsif ($column =~ /^[cq]$/) {
                my $catqueue = $tasks{$task_id}->{'c'} . '-' . $tasks{$task_id}->{'q'};
                push @columns, "<a href=\"$c{baseurl}$catqueue/\">" . $tasks{$task_id}->{$column} . "</a>";
            }
            elsif ($column eq 'v') {
                my $version = $tasks{$task_id}->{$column};
                push @columns, "<a href=\"?version=$version&status=Any&queue=Any\">" . $tasks{$task_id}->{$column} . "</a>";
            }
            elsif ($column eq 'p') {
                my $priority = $tasks{$task_id}->{$column};
                push @columns, "<a href=\"?priority=$priority&status=Any&queue=Any\">" . $tasks{$task_id}->{$column} . "</a>";
            }
            else {
                push @columns, $tasks{$task_id}->{$column};
            }
        }
        update_break_tally($break_tally, $tasks{$task_id});
        push @$rows, \@columns;
        $previous_task_id = $task_id;
    }
    push @$rows, [ "BREAK", 's', 0, $break_tally ];
    return generate_html($titles, $rows);
}

sub cmp_task_column {
    my ($field, $task_a, $task_b) = @_;
    if ($field eq 's' || $fields{$field}->{'type'} eq 'person') {
        return $task_a->{$field} <=> $task_b->{$field};
    }
    elsif ($fields{$field}->{'type'} eq 'enum') {
        return $task_a->{$field} cmp $task_b->{$field};
    }
    else {
        die "unknown comparison"
    }
}

sub update_break_tally {
    my ($tally, $task) = @_;
    foreach my $field (keys %fields) {
        next unless $fields{$field}->{'total'};
        $tally->{$field} += $task->{$field};
    }
}

sub generate_html {
    my ($titles, $rows) = @_;
    
    my $html_top = 
          page_start('WorkLog Report')
        . table_start('minimal', { actions => 1, fund => 1 } )
        . mk_title('WorkLog Report',1)
        ;
    my $table_start   = "<table width=100% border=0>\n";
    my $table_end     = "</table>\n";
    my $column_titles = '<tr nowrap><th>' . join ('</th><th>',@$titles) . "</th></tr>\n";
    my $order         = ''; #$cgi->param('order') || 'c,p';
    my $display       = ''; # $cgi->param('display') || 'c,q,t,im,v,p,su,s';
    my $im            = $cgi->param('im')         || 'Any';
    my $category      = $cgi->param('category')   || 'Any';
    my $status        = $cgi->param('status')     || 'Assigned';
    my $queue         = $cgi->param('queue')      || 'Sprint';
    my $version       = $cgi->param('version')    || 'Any';
    my $priority      = $cgi->param('priority')   || '';
    my $supervisor    = $cgi->param('supervisor') || 'Any';
    my $within        = $cgi->param('within')     || '0';
    my $lastmodified  = $cgi->param('lastmodified')  || 'gt';
    my $archived      = $cgi->param('archived')      || 'n';
    my ($c_lastmodified_gt, $c_lastmodified_lte, $c_archived_y, $c_archived_n) = ();
    $c_lastmodified_lte = 'checked' if $lastmodified eq 'lte';
    $c_lastmodified_gt  = 'checked' if $lastmodified eq 'gt';
    $c_archived_y       = 'checked' if $archived     eq 'y';
    $c_archived_n       = 'checked' if $archived     eq 'n';

    # queue
    my @form_queues = ();
    for ('Any', sort @queues) {
        my $selected = ($_ eq $queue) ? "selected" : "";
        push @form_queues, "<option value=\"$_\" $selected>$_</option>";
    }
    my $form_queue = "<select name=queue>" . join('', @form_queues) . "</select>";

    # category
    my @form_categories = ();
    for ('Any', sort @categories) {
        my $selected = ($_ eq $category) ? "selected" : "";
        push @form_categories, "<option value=\"$_\" $selected>$_</option>";
    }
    my $form_category = "<select name=category>" . join('', @form_categories) . "</select>";

    # version
    my @form_versions = ();
    for ('Any', sort @versions) {
        my $selected = ($_ eq $version) ? "selected" : "";
        push @form_versions, "<option value=\"$_\" $selected>$_</option>";
    }
    my $form_version = "<select name=version>" . join('', @form_versions) . "</select>";

    # status
    my @form_status = ();
    for ('Any', sort values %status) {
        my $selected = ($_ eq $status) ? "selected" : "";
        push @form_status, "<option value=\"$_\" $selected>$_</option>";
    }
    my $form_status = "<select name=status>" . join('', @form_status) . "</select>";

    # im
    my @form_im = ();
    for ('Any', sort keys %ids) {
        my $selected = ($ids{$_} == $im) ? "selected" : "";
        push @form_im, "<option value=\"$ids{$_}\" $selected>$_</option>";
    }
    my $form_im = "<select name=im>" . join('', @form_im) . "</select>";

    # supervisor
    my @form_supervisor = ();
    for ('Any', sort keys %ids) {
        my $selected = ($ids{$_} == $supervisor) ? "selected" : "";
        push @form_supervisor, "<option value=\"$ids{$_}\" $selected>$_</option>";
    }
    my $form_supervisor = "<select name=supervisor>" . join('', @form_supervisor) . "</select>";

    my $form =
          "<FORM>"
        . "<input type=hidden name=order value=\"$order\"><br>"
        . "<input type=hidden name=display value=\"$display\"><br>"
        . "<table width=50%>"
        . "<tr><td align=right>Category&nbsp;<td>$form_category"
        . "<tr><td align=right>Queue&nbsp;<td>$form_queue"
        . "<tr><td align=right>Status&nbsp;<td>$form_status"
        . "<tr><td align=right>Version&nbsp;<td>$form_version"
        . "<tr><td align=right>Priority&nbsp;<td><input type=text name=priority value=\"$priority\" size=5>"
        . "<tr><td align=right>Supervisor&nbsp;<td>$form_supervisor"
        . "<tr><td align=right>Implementor&nbsp;<td>$form_im"
        . "<tr><td align=right>Task last modified&nbsp;<td>"
        . "    <table width=100% border=0><tr><td valign=middle>"
        . "    <input type=radio name=lastmodified value=gt $c_lastmodified_gt>&nbsp;&gt;<br>"
        . "    <input type=radio name=lastmodified value=lte $c_lastmodified_lte>&nbsp;&lt;=<br>"
        . "    <td valign=middle><input type=text name=within value=\"$within\" size=5> days ago"
        . "    </table>"
        . "<tr><td align=right>Archived&nbsp;<td>"
        . "    <table width=100% border=0><tr><td valign=middle>"
        . "    <input type=radio name=archived value=y $c_archived_y>&nbsp;True<br>"
        . "    <input type=radio name=archived value=n $c_archived_n>&nbsp;False<br>"
        . "    </table>"
        . "<tr><td>&nbsp;<td><input type=submit name=button value=Submit>"
        . "</table>"
        . "</FORM>"
        ;


    my $html = $html_top . $form . $table_start . $column_titles;

    foreach my $columns (@$rows) {
        if ($columns->[0] eq 'BREAK') {
            last;
            my (undef, $field, $level, $tally) = @$columns;
            $html .= $table_end;
            # $html .= mk_title $fields{$field}->{'title'};
            $html .= $table_start;
            $html .= html_tally($tally);
            $html .= $table_end . $table_start . $column_titles;
        }
        else {
            $html .= '<tr nowrap><td nowrap>' . join ('</td><td nowrap>',@$columns) . "</td></tr>\n";
        }
    }
    
    $html .= $table_end . page_end('none');
    return $html;
}

sub html_tally {
    my ($tally) = @_;
    my $html    = '';
    my %titles  = ();
    foreach (keys %$tally) {
        $titles{$fields{$_}->{'title'}} = $tally->{$_};
    }
    $html .= '<tr nowrap><th>' . join ('</th><th>',sort keys %titles) . "</th></tr>\n";
    $html .= '<tr nowrap><td>' . join ('</td><td>',@titles{sort keys %titles}) . "</td></tr>\n";
}

sub pretty_date {
    my ($rough_date) = @_;
    my ($year, $month, $day, $hour, $minute, $seconds) = ();
    if (($year, $month, $day, $hour, $minute, $seconds) = 
      $rough_date =~ /^(\d\d\d\d)(\d\d)(\d\d) (\d\d):(\d\d):(\d\d)$/) {
        return
            join('-', $year, $month, $day)
            . ' '
            . join(':', $hour, $minute, $seconds)
            ;
    }
    else {
        return '';
    }
}

sub status {
    my ($id) = @_;
    return $status{$id};
}

sub childof {
    my ($parent) = @_;
    return () unless defined $childof->{$parent};
    return @{ $childof->{$parent} };
}

sub parentof {
    my ($child) = @_;
    return () unless defined $parentof->{$child};
    return @{ $parentof->{$child} };
}

sub initialize {
    my ($sql, $sth) = ();

    $columnre = join '|', keys %fields;
    $columnre = qr/$columnre/i;

    $dbh = new WorkLog::Database;
    $cgi = new WorkLog::CGI;

    $sql = 'SELECT id, username FROM user';
    $sth = $dbh->prepare($sql);
    $sth->execute();
    while ( my @row = $sth->fetchrow_array ) {
        my ($id, $username) = @row;
        $usernames{$id} = $username;
        $ids{$username} = $id;
    }
    $sth->finish;

    $sql = 'SELECT parent, child FROM depends';
    $sth = $dbh->prepare($sql);
    $sth->execute();
    while ( my ($parent, $child) = $sth->fetchrow_array ) {
        push @{ $childof->{$parent} }, $child;
        push @{ $parentof->{$child} }, $parent;
    }
    $sth->finish;

    $sql = 'SELECT id, status FROM status';
    $sth = $dbh->prepare($sql);
    $sth->execute();
    while ( my ($id, $status) = $sth->fetchrow_array ) {
        $status{$id} = $status;
    }
    $sth->finish;

    # categories
    $sql = 'SELECT distinct category FROM categories';
    $sth = $dbh->prepare($sql);
    $sth->execute();
    while ( my ($category) = $sth->fetchrow_array ) {
        push @categories, $category;
    }
    $sth->finish;

    # queues
    $sql = 'SELECT distinct queue FROM categories';
    $sth = $dbh->prepare($sql);
    $sth->execute();
    while ( my ($queue) = $sth->fetchrow_array ) {
        push @queues, $queue;
    }
    $sth->finish;

    # version
    $sql = 'SELECT DISTINCT version FROM tasks';
    $sth = $dbh->prepare($sql);
    $sth->execute();
    while ( my ($version) = $sth->fetchrow_array ) {
        push @versions, $version;
    }
    $sth->finish;

    foreach my $column (keys %fields) {
        my @field_data = @{$fields{$column}};
        $fields{$column} = {};
        my $entry = $fields{$column};
        $entry->{'title'} = $field_data[0];
        $entry->{'type'} = $field_data[1];
        $entry->{'break'} = $field_data[2];
        $entry->{'total'} = $field_data[3];
        $entry->{'fwhere'} = $field_data[4];
        $entry->{'ftype'} = $field_data[5];
        $entry->{'field'} = $field_data[6];
    }

    1;
}

sub import {
    unless ($inited) {
        initialize;
    }
    $inited++;
}

1;
