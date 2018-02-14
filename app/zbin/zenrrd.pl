#!/usr/bin/perl
###############################################################################
#
#    Zevenet Software License
#    This file is part of the Zevenet Load Balancer software package.
#
#    Copyright (C) 2014-today ZEVENET SL, Sevilla (Spain)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

#this script run all pl files with -rrd.pl regexh in $rrdap_dir,
#this -rrd.pl files will create the rrd graphs that zen load balancer gui
#will paint in Monitoring section
#USE:
#you have to include in the cron user this next line for example:
#execution over 2 minutes
#*/2 * * * * /usr/local/zevenet/app/rrd/zenrrd.pl
#Fell free to create next graphs, in files type
#name-rrd.pl, the system going to include automatically to execute
#and viewing in Zen load balancer GUI (Monitoring secction)

use strict;
use warnings;
use Zevenet::Config;

my $rrdap_dir = &getGlobalConfiguration('rrdap_dir');
my $lockfile = "/tmp/rrd.lock";

if ( -e $lockfile )
{
	print "RRD Locked by $lockfile, maybe other zenrrd in execution\n";
	exit;
}
else
{
	open my $lock, '>', $lockfile;
	print $lock "lock rrd";
	close $lock;
}

opendir ( my $dir, $rrdap_dir );
my @rrd_scripts = grep ( /-rrd.pl$/, readdir ( $dir ) );
closedir ( $dir );

foreach my $script_rrd ( @rrd_scripts )
{
	print "Executing $script_rrd...\n";

	system( "$rrdap_dir/$script_rrd" );
}

if ( -e $lockfile )
{
	unlink ( $lockfile );
}