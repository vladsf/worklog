#
# WLCONFIG.pm
#
# This conf file is part of the WorkLog software.
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
package WLCONFIG;
#DEVONLY use warnings;
use strict;
use vars qw(%conf);

our $VERSION = sprintf "%d.%03d", q$Revision: 1.14 $ =~ /(\d+)/g;
my $public_version = '3.5.9';  # SET BY RELEASE BUILD

########################################################################
######## Misc. Definitions
my $DEBUG       = 0;
my $user        = 'worklog';
my $auth        = 'password';
my $host        = 'localhost';
my $db          = 'mysql';
my $dbname      = 'worklog';
my $dsn         = "DBI:${db}:${dbname}:host=${host}";
my $finstat     = 'Complete';
my $finstat_num = '5';
my $strtstat    = '1';
my $view_limit  = '15';
my $logo        = 'images/mini-mysql.png';
my $headqu      = 'MySQL headquarters (Uppsala, Sweden)';
my $bugsdb      = 'http://bugs.mysql.com/bug.php?id=';
my $repos       = '/repos/';
my $hthost      = defined $ENV{HTTP_HOST} ? $ENV{HTTP_HOST} : "localhost";
my $httphost    = (    defined $ENV{HTTPS}    && $ENV{HTTPS}    eq 'on'
                    or defined $ENV{HTTP_SSL} && $ENV{HTTP_SSL} eq 'on')
                    ? "https://$hthost" : "http://$hthost";
my $baseurl     = '/worklog/';
my $prjhttp     = 'http://worklog.sourceforge.net/';
my $ok_button   = "<input type=\"submit\" style=\"background-color: #f0f0f0\" value=\"&#160;&#160;OK&#160;&#160;\">";
my $canc_button = "<input type=\"button\" style=\"background-color: #f0f0f0\" value=\"Cancel\" onClick=\"window.history.back()\">";

#   handle        regex idents
my $mail_idents = {
    'task' => {
        rip_id   => '(wl|worklog|\s)?>\s+TASK...........:\s.+',
        type     => 'simple',
        pattern  => '.*',
        ptype    => 'static',
        active   => 0,
        newtask  => 1,
        required => 1,
        owner    => 1,
        callback => \&WORKLOG::wk_update_title,
    },
    'assby' => {
        rip_id   => '(wl|worklog|\s)?>\s+ASSIGNED\sBY....:\s.+',
        type     => 'list',
        pattern  => 'SELECT username FROM user',
        ptype    => 'dynamic',
        active   => 1,
        newtask  => 1,
        required => 0,
        owner    => 0,
        callback => \&WORKLOG::wk_update_assby,
    },
    'assto' => {
        rip_id   => '(wl|worklog|\s)?>\s+ASSIGNED\sTO....:\s.+',
        type     => 'list',
        pattern  => 'SELECT username FROM user',
        ptype    => 'multidynamic',
        active   => 1,
        newtask  => 1,
        required => 0,
        owner    => 0,
        callback => \&WORKLOG::wk_update_assto,
    },
    'copto' => {
        rip_id   => '(wl|worklog|\s)?>\s+COPIES\sTO......:\s.+',
        type     => 'list',
        pattern  => 'SELECT username FROM user',
        ptype    => 'multidynamic',
        active   => 0,
        newtask  => 1,
        required => 0,
        owner    => 1,
        callback => \&WORKLOG::wk_update_null,
    },
    'category' => {
        rip_id   => '(wl|worklog|\s)?>\s+CATEGORY.......:\s.+',
        type     => 'conv',
        pattern  => '.*',
        ptype    => 'static',
        active   => 0,
        newtask  => 1,
        required => 0,
        owner    => 1,
        convcb   => \&WORKLOG::conv_catid,
        callback => \&WORKLOG::wk_update_category,
    },
    'status' => {
        rip_id   => '(wl|worklog|\s)?>\s+STATUS.........:\s.+',
        type     => 'conv',
        pattern  => 'SELECT status FROM status',
        ptype    => 'dynamic',
        active   => 1,
        newtask  => 1,
        required => 0,
        owner    => 0,
        convcb   => \&WORKLOG::conv_status,
        callback => \&WORKLOG::wk_update_status,
    },
    'prio' => {
        rip_id   => '(wl|worklog|\s)?>\s+PRIORITY.......:\s.+',
        type     => 'conv',
        pattern  => 'SELECT priority FROM priority',
        ptype    => 'dynamic',
        active   => 1,
        newtask  => 1,
        required => 0,
        owner    => 0,
        convcb   => \&WORKLOG::conv_prio,
        callback => \&WORKLOG::wk_update_prio,
    },
    'descrip' => {
        rip_id   => '(wl|worklog|\s)?>\s+DESCRIPTION:',
        type     => 'ettext',
        pattern  => '.*',
        ptype    => 'static',
        active   => 0,
        newtask  => 1,
        required => 1,
        owner    => 1,
        callback => \&WORKLOG::wk_update_null,
    },
    'pnote' => {
        rip_id   => '(wl|worklog|\s)?>\s+PROGRESS\sNOTES:',
        type     => 'ettext',
        pattern  => '.*',
        ptype    => 'static',
        active   => 1,
        newtask  => 1,
        required => 0,
        owner    => 0,
        callback => \&WORKLOG::wk_update_pnote,
    },
    'devtime' => {
        rip_id   => '(wl|worklog|\s)?>\s+TIME..........:\s.+',
        type     => 'simple',
        pattern  => '\d*',
        ptype    => 'static',
        active   => 1,
        newtask  => 1,
        required => 0,
        owner    => 1,
        callback => \&WORKLOG::wk_update_devtime,
    },
    'docopti' => {
        rip_id   => '(wl|worklog|\s)?>\s+OPTIMISTIC....:\s.+',
        type     => 'simple',
        pattern  => '(\d{4}\-\d{2}\-\d{2})|()',
        ptype    => 'static',
        active   => 1,
        newtask  => 1,
        required => 0,
        owner    => 0,
        callback => \&WORKLOG::wk_update_dopti,
    },
    'docreal' => {
        rip_id   => '(wl|worklog|\s)?>\s+REALISTIC.....:\s.+',
        type     => 'simple',
        pattern  => '(\d{4}\-\d{2}\-\d{2})|()',
        ptype    => 'static',
        active   => 1,
        newtask  => 1,
        required => 0,
        owner    => 0,
        callback => \&WORKLOG::wk_update_dreal,
    },
    'docabso' => {
        rip_id   => '(wl|worklog|\s)?>\s+ABSOLUTE......:\s.+',
        type     => 'simple',
        pattern  => '(\d{4}\-\d{2}\-\d{2})|()',
        ptype    => 'static',
        active   => 1,
        newtask  => 1,
        required => 0,
        owner    => 0,
        callback => \&WORKLOG::wk_update_dabso,
    },
};

#                   Prio          NUM
my $prio_conv = {
    'very high' => 90,
    'high'      => 80,
    'medium'    => 60,
    'low'       => 50,
    'very low'  => 25,
};
my $versions = {
    'Server' => [
        '7.1',   '7.0',   '6.1',   '6.0', '5.2', '5.1',
        '5.0', '4.2', '4.1', '4.0',
    ],
    'Connector/J'    => [ '3.2',  '3.1' ],
    'Connector/ODBC' => [ '3.53', '3.52' ],
    'Connector/.NET' => [ '2.1',  '2.0', '1.6' ],
    'GUI-Tools'        => [ '3.0',  '2.0' ],
    'Benchmarks'     => [ '3.0',  '2.0' ],
    'WorkLog'        => [ '3.4',  '3.5', '3.6', '4.0', '4.1' ],
};

my $default_versions = {
    'Server' => [
        'Server-RawIdeaBin',   'Server-BackLog',
        'Server-Sprint',       'Replication-RawIdeaBin',
        'Replication-BackLog', 'Replication-Sprint',
        'APIs-RawIdeaBin',     'APIs-BackLog',
        'APIs-Sprint',         'Client-RawIdeaBin',
        'Client-BackLog',      'Client-Sprint',
        'Win32-RawIdeaBin',    'Win32-BackLog',
        'Win32-Sprint',        'Docs-RawIdeaBin',
        'Docs-BackLog',        'Docs-Sprint',
    ],
    'Connector/J'    => [ 'JDBC-RawIdeaBin', 'JDBC-BackLog', 'JDBC-Sprint' ],
    'Connector/ODBC' => [ 'ODBC-RawIdeaBin', 'ODBC-BackLog', 'ODBC-Sprint' ],
    'Connector/.NET' => [ '.NET-RawIdeaBin', '.NET-BackLog', '.NET-Sprint' ],
    'GUI-Tools' => [ 'GUI-Tools-RawIdeaBin', 'GUI-Tools-BackLog', 'GUI-Tools-Sprint' ],
    'Benchmarks' => [
        'Benchmarks-RawIdeaBin',
        'Benchmarks-BackLog',
        'Benchmarks-Sprint',
    ],
    'WorkLog' => [ 'WorkLog-RawIdeaBin', 'WorkLog-BackLog', 'WorkLog-Sprint' ],
};

my $default_versions2 = {
    'Server'      =>  'Server',
    'Replication' =>  'Server',
    'APIs'        =>  'Server',
    'Client'      =>  'Server',
    'Win32'       =>  'Server',
    'Docs'        =>  'Server',
    'JDBC'        =>  'Connector/J',
    'ODBC'        =>  'Connector/ODBC',
    '.NET'        =>  'Connector/.NET',
    'GUI-Tools'   =>  'GUI-Tools',
    'Benchmarks'  =>  'Benchmarks',
    'WorkLog'     =>  'WorkLog',
};

########################################################################
######## Color Definitions
my $color_amber    = 'orange';
my $color_green    = 'green';
my $color_ltgreen  = '#f4f4ee';
my $color_red      = 'red';
my $color_dred     = 'darkred';
my $color_blue     = 'blue';
my $color_ltblue   = '#e2e9eb';
my $color_elblue   = '#2040ff';
my $color_black    = 'black';
my $color_white    = 'white';
my $color_ltgrey   = 'lightgrey';
my $color_fgold    = '#d6c9a7';
my $color_grey     = '#707070';
my $color_purple   = '#310063';
my $color_yellow   = '#ffcc00';
my $color_mysqlred = '#8d0404';
my $color_mysqlgld = '#df9700';
my $color_mysqlblu = '#006486';

########################################################################
######## View string lengths
my $strlen_devname = 12;
my $strlen_grpldr  = 12;
my $strlen_status  = 10;
my $strlen_prio    = 8;
my $strlen_title   = 40;
my $strlen_etitle  = 48;

########################################################################
######## Title font sizes
my $size_big   = 2;
my $size_small = 0;

########################################################################
######## Email text
my $email_domain      = 'mysql.com';
my $cooky_domain      = 'mysql.com';
my $email_from        = "worklog-noreply\@$email_domain";
my $email_db          = "worklog-db\@$email_domain";
my $email_subid       = '[WORKLOG]';
my $email_smtp        = 'localhost';
my $email_header_task = <<END_HEADER;
-----------------------------------------------------------------------
END_HEADER

my $email_footer_task = <<END_FOOTER;
WorkLog (v$public_version)
END_FOOTER

########################################################################
######## Configuration Hash

%conf = (
    db => {
        dsn  => $dsn,
        user => $user,
        auth => $auth,
    },
    button => {
        ok     => $ok_button,
        cancel => $canc_button,
    },
    misc => {
        DEBUG       => $DEBUG,
        bugsdb      => $bugsdb,
        version     => $public_version,
        view_limit  => $view_limit,
        DAYS_VIEW   => 10,
        H_OFF       => 5,
        finstat     => $finstat,
        finstat_num => $finstat_num,
        strtstat    => $strtstat,
        httphost    => $httphost,
        baseurl     => $baseurl,
        dbemail     => $email_db,
        repos       => $repos,
        prjhttp     => $prjhttp,
        style       => "<style type=\"text/css\">
A:link {color: $color_mysqlblu; text-decoration: none}
A:visited {color: $color_mysqlblu; text-decoration: none}
A:active {color: $color_grey; text-decoration: none}
body,th,td,div,p,h1,h2,li,dt,dd {
 font-family: Tahoma, Verdana, Arial, Helvetica, sans-serif;
 font-size: 12px;
}
ul {
 list-style-image: url(images/box.png);
 list-style-type: square;
}
INPUT,SELECT {
font-family: Tahoma, Verdana, Arial, Helvetica, sans-serif;
font-size: 12px;
color: #404040;
background-color: #FFFFFF;
border: #006486 solid;
border-width: 1px 1px 1px 1px;
}
TEXTAREA {
font-family: Courier;
font-size: 12px;
color: #404040;
background-color: #FFFFFF;
border: #006486 solid;
border-width: 1px 1px 1px 1px;
}
acronym:hover, abbr:hover {cursor: help}
abbr[title], acronym[title], span[title], strong[title] {
font-style: normal;
}
</style>",
        mail_idents      => $mail_idents,
        prio_conv        => $prio_conv,
        versions         => $versions,
        default_versions => $default_versions2,
    },
    err => {
        noid => 'Sorry, I don\'t have that Task ID.',
    },
    color => {
        amber    => $color_amber,
        green    => $color_green,
        ltgreen  => $color_ltgreen,
        red      => $color_red,
        dred     => $color_dred,
        blue     => $color_blue,
        ltblue   => $color_ltblue,
        elblue   => $color_elblue,
        black    => $color_black,
        white    => $color_white,
        ltgrey   => $color_ltgrey,
        fgold    => $color_fgold,
        grey     => $color_grey,
        purple   => $color_purple,
        yellow   => $color_yellow,
        mysqlred => $color_mysqlred,
        mysqlgld => $color_mysqlgld,
        mysqlblu => $color_mysqlblu,
    },
    images => {
        logo => {
            src    => $logo,
            height => 65,
            width  => 125,
        },
        bkg => {
            src => 'images/bkg.gif',
        },
        ul => {
            src    => 'images/ul.gif',
            height => 10,
            width  => 10,
        },
        ur => {
            src    => 'images/ur.gif',
            height => 10,
            width  => 10,
        },
        ll => {
            src    => 'images/ll.gif',
            height => 10,
            width  => 10,
        },
        lr => {
            src    => 'images/lr.gif',
            height => 10,
            width  => 10,
        },
    },
    body => {
        bg    => $color_white,
        txt   => $color_black,
        link  => $color_mysqlgld,
        alink => $color_ltgrey,
        vlink => $color_mysqlgld,
    },
    title => {
        bg         => $color_mysqlblu,
        txt        => $color_black,
        bg_anti    => $color_white,
        hdr_txt    => $color_black,
        face       => 'Helvetica,Arial',
        size_big   => $size_big,
        size_small => $size_small,
    },
    prio_clr => {
        verylow  => $color_blue,
        low      => $color_green,
        medium   => $color_grey,
        high     => $color_amber,
        veryhigh => $color_red,
        complete => $color_blue,
        none     => $color_black,
    },
    prio_txt => {
        verylow  => 'Very Low',
        low      => 'Low',
        medium   => 'Medium',
        high     => 'High',
        veryhigh => 'Very High',
        complete => 'Complete',
        none     => 'None',
    },
    strlen => {
        devname => $strlen_devname,
        grpldr  => $strlen_grpldr,
        status  => $strlen_status,
        title   => $strlen_title,
        etitle  => $strlen_etitle,
        prio    => $strlen_prio,
    },
    email => {
        header_task => $email_header_task,
        footer_task => $email_footer_task,
        from        => $email_from,
        subid       => $email_subid,
        domain      => $email_domain,
        cdomain     => $cooky_domain,
        smtp        => $email_smtp,
    },
);

sub release {
    return $public_version;
}

1;
