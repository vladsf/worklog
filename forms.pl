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
no warnings 'uninitialized';
use strict;

BEGIN {
    push @INC, -f "/usr/local/etc/WLCONFIG.pm" ? "/usr/local/etc" : "./lib";
}

use WLCONFIG;
use vars qw(%c);
*c = \%WLCONFIG::conf;
use WorkLog::Database;
use WorkLog::CGI;
use WorkLog::Forms qw(
    add_depends
    arch_task
    cat_add
    cat_del
    cate_change
    cat_form
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
    progrep_add
    progrep_form
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
    version_change
);

use WorkLog qw(
    error
);

local $SIG{__DIE__} = sub {
    my $errmsg = shift;
    error($errmsg);
    exit 1;
};

my $cgi = new WorkLog::CGI;
my $dbh = new WorkLog::Database;

my $views  = "$c{misc}{baseurl}index.pl";

########################################################################
######## Main dispatcher code

my $form = $cgi->param('form');

if ( $form eq '' ) {
    print $cgi->redirect($views);
}
else {
    if ( $form eq 'fid' ) {
        file_redir;
    }
    elsif ( $form eq 'delete' ) {
        delete_form;
    }
    elsif ( $form eq 'realdelete' ) {
        delete_task;
    }
    elsif ( $form eq 'changeobservers' ) {
        change_observers;
    }
    elsif ( $form eq 'observ' ) {
        if ( $cgi->param('addme') ) {
            observ_addme;
        }
        elsif ( $cgi->param('removeme') ) {
            observ_removeme;
        }
        else {
            observ_form;
        }
    }
    elsif ( $form eq 'removeobs' ) {
        observ_remove($cgi->param('tid'), $cgi->param('devid'));
        print $cgi->redirect($cgi->referer);
    }
    elsif ( $form eq 'deldev' ) {
        dev_del;
    }
    elsif ( $form eq 'delcat' ) {
        cat_del;
    }
    elsif ( $form eq 'addcat' ) {
        if ( $cgi->param('newcat') ) {
            cat_add;
        }
        else {
            cat_form;
        }
    }
    elsif ( $form eq 'addtask' ) {
        if ( $cgi->param('title') ) {
            task_add;
        }
        else {
            task_form;
        }
    }
    elsif ( $form eq 'reqnew' ) {
        task_add_email;
    }
    elsif ( $form eq 'reqnewform' ) {
        task_add_email_form;
    }
    elsif ( $form eq 'reqcopy' ) {
        task_copy_email;
    }
    elsif ( $form eq 'reqcopyform' ) {
        task_copy_email_form;
    }
    elsif ( $form eq 'addprogrep' ) {
        if ( $cgi->param('text') ) {
            progrep_add;
        }
        else {
            # print $cgi->redirect($cgi->referer);
            progrep_form;
        }
    }
    elsif ( $form eq 'chgrpldr' ) {
        if ( $cgi->param('grpldr') ) {
            grpldr_change;

            #      } else {
            #        &status_form;
        }
    }
    elsif ( $form eq 'chversion' ) {
        if ( $cgi->param('version') ) {
            version_change;

            #      } else {
            #        &status_form;
        }
    }
    elsif ( $form eq 'chstatus' ) {
        if ( $cgi->param('status') ) {
            status_change;

            #      } else {
            #        &status_form;
        }
    }
    elsif ( $form eq 'chcate' ) {
        if ( $cgi->param('cate') ) {
            cate_change;

            #      } else {
            #        &cate_form;
        }
    }
    elsif ( $form eq 'chdates' ) {
        if ( $cgi->param('dopti')
            || $cgi->param('dreal')
            || $cgi->param('dabso') )
        {
            dates_change;

            #      } else {
            #        &dates_form;
        }
    }
    elsif ( $form eq 'chtime' ) {
        if ( defined $cgi->param('time') ) {
            time_change;

            #      } else {
            #        &time_form;
        }
    }
    elsif ( $form eq 'chdescrip' ) {
        if ( $cgi->param('descrip') ) {
            descrip_change;
        }
    }
    elsif ( $form eq 'chhla' ) {
        if ( $cgi->param('hla') ) {
            hla_change;
        }
    }
    elsif ( $form eq 'chlld' ) {
        if ( $cgi->param('lld') ) {
            lld_change;
        }
    }
    elsif ( $form eq 'chtitle' ) {
        if ( $cgi->param('title') ) {
            title_change;

            #      } else {
            #        &prio_form;
        }
    }
    elsif ( $form eq 'chprio' ) {
        if ( $cgi->param('prio') ) {
            prio_change;

            #      } else {
            #        &prio_form;
        }
    }
    elsif ( $form eq 'reassign' ) {
        if ( $cgi->param('newowner') ) {
            reassign_change;
        }
        else {
            reassign_form;
        }
    }
    elsif ( $form eq 'archtask' ) {
        arch_task;
    }
#    elsif ( $form eq 'addday' ) {
#        if ( $cgi->param('text') ) {
#            day_add;
#        }
#        else {
#            day_form;
#        }
#    }
    elsif ( $form eq 'chtask' ) {
        task_change;
    }
    elsif ( $form eq 'adddepends' ) {
        add_depends;
    }
    elsif ( $form eq 'deldepends' ) {
        del_depends;
    }
    elsif ( $form eq 'attachfile' ) {
        file_attach;
    }
    elsif ( $form eq 'download' ) {
        file_download;
    }
    elsif ( $form eq 'deletefile' ) {
        file_delete;
    }
    elsif ( $form eq 'burndown' ) {
        print $cgi->redirect("$c{misc}{baseurl}burndown.pl?tid=" . $cgi->param('tid'));
    }
    elsif ( $form eq 'sql' ) {
        sql_form;
    }
#    elsif ( $form eq 'workdone' ) {
#        &workdone;
#    }
#    elsif ( $form eq 'worknotdone' ) {
#        &worknotdone;
#    }
#    elsif ( $form eq 'updatetime' ) {
#        updatetime_form;
#    }
#    elsif ( $form eq 'updatetime_change' ) {
#        updatetime_change;
#    }
    else {
        error("Form: $form");
    }
}

