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

use strict;

my $configdir = &getGlobalConfiguration('configdir');

=begin nd
Function: _runDatalinkFarmStart

	Run a datalink farm
	
Parameters:
	farmname - Farm name
	writeconf - If this param has the value "true" in config file will be saved the current status

Returns:
	Integer - Error code: return 0 on success or different of 0 on failure
	
BUG: 
	writeconf must not exist, always it has to be TRUE 
	status parameter is not useful
	
=cut
sub _runDatalinkFarmStart    # ($farm_name, $writeconf, $status)
{
	my ( $farm_name, $writeconf ) = @_;

	require Tie::File;
	require Zevenet::Net::Util;
	require Zevenet::Farm::Datalink::Config;
	require Zevenet::Farm::Datalink::Backend;

	my $status;
	my $farm_filename = &getFarmFile( $farm_name );

	if ( $writeconf eq "true" )
	{
		tie my @configfile, 'Tie::File', "$configdir\/$farm_filename";
		my $first = 1;

		foreach ( @configfile )
		{
			if ( $first eq 1 )
			{
				s/\;down/\;up/g;
				$first = 0;
			}
		}
		untie @configfile;
	}

	# include cron task to check backends
	tie my @cron_file, 'Tie::File', "/etc/cron.d/zevenet";
	my @farmcron = grep /\# \_\_$farm_name\_\_/, @cron_file;

	if ( scalar @farmcron eq 0 )
	{
		push ( @cron_file,
			   "* * * * *	root	\/usr\/local\/zevenet\/app\/libexec\/check_uplink $farm_name \# \_\_$farm_name\_\_"
		);
	}
	untie @cron_file;

	# Apply changes online
	# Set default uplinks as gateways
	my $iface     = &getDatalinkFarmInterface( $farm_name );
	my $ip_bin    = &getGlobalConfiguration('ip_bin');
	my @eject     = `$ip_bin route del default table table_$iface 2> /dev/null`;
	my @servers   = &getDatalinkFarmServers( $farm_name );
	my $algorithm = &getDatalinkFarmAlgorithm( $farm_name );
	my $routes    = "";

	if ( $algorithm eq "weight" )
	{
		foreach my $serv ( @servers )
		{
			chomp ( $serv );
			my @line = split ( "\;", $serv );
			my $stat = $line[5];
			chomp ( $stat );
			my $weight = 1;

			if ( $line[3] ne "" )
			{
				$weight = $line[3];
			}
			if ( $stat eq "up" )
			{
				$routes = "$routes nexthop via $line[1] dev $line[2] weight $weight";
			}
		}
	}

	if ( $algorithm eq "prio" )
	{
		my $bestprio = 100;
		foreach my $serv ( @servers )
		{
			chomp ( $serv );
			my @line = split ( "\;", $serv );
			my $stat = $line[5];
			my $prio = $line[4];
			chomp ( $stat );

			if (    $stat eq "up"
				 && $prio > 0
				 && $prio < 10
				 && $prio < $bestprio )
			{
				$routes   = "nexthop via $line[1] dev $line[2] weight 1";
				$bestprio = $prio;
			}
		}
	}

	if ( $routes ne "" )
	{
		my $ip_command =
		  "$ip_bin route add default scope global table table_$iface $routes";

		&zenlog( "running $ip_command" );
		$status = system ( "$ip_command >/dev/null 2>&1" );
	}
	else
	{
		$status = 0;
	}

	# Set policies to the local network
	my $ip = &iponif( $iface );

	if ( $ip && $ip =~ /\./ )
	{
		use Net::IPv4Addr qw(ipv4_network); # Does not support 'require'

		my $ipmask = &maskonif( $iface );
		my ( $net, $mask ) = ipv4_network( "$ip / $ipmask" );
		&zenlog( "running $ip_bin rule add from $net/$mask lookup table_$iface" );
		my @eject = `$ip_bin rule add from $net/$mask lookup table_$iface 2> /dev/null`;
	}

	# Enable IP forwarding
	&setIpForward( "true" );

	# Enable active datalink file
	my $piddir = &getGlobalConfiguration('piddir');
	open FI, ">$piddir\/$farm_name\_datalink.pid";
	close FI;

	return $status;
}

=begin nd
Function: _runDatalinkFarmStop

	Stop a datalink farm
	
Parameters:
	farmname - Farm name
	writeconf - If this param has the value "true" in config file will be saved the current status

Returns:
	Integer - Error code: return 0 on success or -1 on failure
	
BUG: 
	writeconf must not exist, always it has to be TRUE 
	
=cut
sub _runDatalinkFarmStop    # ($farm_name,$writeconf)
{
	my ( $farm_name, $writeconf ) = @_;

	require Tie::File;
	require Zevenet::Net::Util;
	require Zevenet::Farm::Datalink::Config;

	my $farm_filename = &getFarmFile( $farm_name );
	my $status = ( $writeconf eq "true" ) ? -1 : 0;

	if ( $writeconf eq "true" )
	{
		tie my @configfile, 'Tie::File', "$configdir\/$farm_filename";
		my $first = 1;
		foreach ( @configfile )
		{
			if ( $first == 1 )
			{
				s/\;up/\;down/g;
				$status = $?;
				$first  = 0;
			}
		}
		untie @configfile;
	}

	# delete cron task to check backends
	tie my @cron_file, 'Tie::File', "/etc/cron.d/zevenet";
	@cron_file = grep !/\# \_\_$farm_name\_\_/, @cron_file;
	untie @cron_file;

	$status = 0 if $writeconf eq 'false';

	# Apply changes online
	if ( $status == -1 )
	{
		return $status;
	}

	my $iface = &getDatalinkFarmInterface( $farm_name );
	my $ip_bin = &getGlobalConfiguration('ip_bin');

	# Disable policies to the local network
	my $ip = &iponif( $iface );

	if ( $ip && $ip =~ /\./ )
	{
		my $ipmask = &maskonif( $iface );
		my ( $net, $mask ) = ipv4_network( "$ip / $ipmask" );

		&zenlog( "running $ip_bin rule del from $net/$mask lookup table_$iface" );
		my @eject = `$ip_bin rule del from $net/$mask lookup table_$iface 2> /dev/null`;
	}

	# Disable default uplink gateways
	my @eject = `$ip_bin route del default table table_$iface 2> /dev/null`;

	# Disable active datalink file
	my $piddir = &getGlobalConfiguration('piddir');
	unlink ( "$piddir\/$farm_name\_datalink.pid" );

	if ( -e "$piddir\/$farm_name\_datalink.pid" )
	{
		$status = -1;
	}

	return $status;
}

=begin nd
Function: setDatalinkNewFarmName

	Function that renames a farm
	
Parameters:
	farmname - Farm name
	newfarmname - New farm name

Returns:
	Integer - Error code: return 0 on success or -1 on failure
	
=cut
sub setDatalinkNewFarmName    # ($farm_name,$new_farm_name)
{
	my ( $farm_name, $new_farm_name ) = @_;

	require Tie::File;

	my $farm_filename = &getFarmFile( $farm_name );
	my $farm_type     = &getFarmType( $farm_name );
	my $newffile      = "$new_farm_name\_$farm_type.cfg";
	my $output        = -1;

	tie my @configfile, 'Tie::File', "$configdir\/$farm_filename";

	for ( @configfile )
	{
		s/^$farm_name\;/$new_farm_name\;/g;
	}
	untie @configfile;

	my $piddir = &getGlobalConfiguration('piddir');
	rename ( "$configdir\/$farm_filename", "$configdir\/$newffile" );
	rename ( "$piddir\/$farm_name\_$farm_type.pid",
			 "$piddir\/$new_farm_name\_$farm_type.pid" );
	$output = $?;

	return $output;
}

1;
