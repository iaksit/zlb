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
Function: getDatalinkFarmAlgorithm

	Get type of balancing algorithm. 
	
Parameters:
	farmname - Farm name

Returns:
	scalar - The possible values are "weight", "priority" or -1 on failure
	
=cut
sub getDatalinkFarmAlgorithm    # ($farm_name)
{
	my ( $farm_name ) = @_;

	my $farm_filename = &getFarmFile( $farm_name );
	my $algorithm     = -1;
	my $first         = "true";

	open FI, "<$configdir/$farm_filename";

	while ( my $line = <FI> )
	{
		if ( $line ne "" && $first eq "true" )
		{
			$first = "false";
			my @line = split ( "\;", $line );
			$algorithm = $line[3];
		}
	}
	close FI;

	return $algorithm;
}

=begin nd
Function: setDatalinkFarmAlgorithm

	Set the load balancing algorithm to a farm
	
Parameters:
	algorithm - Type of balancing mode: "weight" or "priority"
	farmname - Farm name

Returns:
	none - .
	
FIXME:
	set a return value, and do error control
	
=cut
sub setDatalinkFarmAlgorithm    # ($algorithm,$farm_name)
{
	my ( $algorithm, $farm_name ) = @_;

	require Tie::File;

	my $farm_filename = &getFarmFile( $farm_name );
	my $i = 0;

	tie my @configfile, 'Tie::File', "$configdir\/$farm_filename";

	for my $line ( @configfile )
	{
		if ( $line =~ /^$farm_name\;/ )
		{
			my @args = split ( "\;", $line );
			$line = "$args[0]\;$args[1]\;$args[2]\;$algorithm\;$args[4]";
			splice @configfile, $i, $line;
		}
		$i++;
	}
	untie @configfile;

	# Apply changes online
	if ( &getFarmStatus( $farm_name ) eq 'up' )
	{
		require Zevenet::Farm::Action;
		&runFarmStop( $farm_name, "true" );
		&runFarmStart( $farm_name, "true" );
	}

	return;
}

=begin nd
Function: getDatalinkFarmBootStatus

	Return the farm status at boot zevenet
	 
Parameters:
	farmname - Farm name

Returns:
	scalar - return "down" if the farm not run at boot or "up" if the farm run at boot

=cut
sub getDatalinkFarmBootStatus    # ($farm_name)
{
	my ( $farm_name ) = @_;

	my $farm_filename = &getFarmFile( $farm_name );
	my $output        = "down";
	my $first         = "true";

	open FI, "<$configdir/$farm_filename";

	while ( my $line = <FI> )
	{
		if ( $line ne "" && $first eq "true" )
		{
			$first = "false";
			my @line_a = split ( /;/, $line );
			$output = $line_a[4];
			chomp ( $output );
		}
	}
	close FI;

	return $output;
}

=begin nd
Function: getDatalinkFarmInterface

	 Get network physical interface used by the farm vip
	 
Parameters:
	farmname - Farm name

Returns:
	scalar - return NIC inteface or -1 on failure

=cut
sub getDatalinkFarmInterface    # ($farm_name)
{
	my ( $farm_name ) = @_;

	my $type   = &getFarmType( $farm_name );
	my $output = -1;
	my $line;

	if ( $type eq "datalink" )
	{
		my $farm_filename = &getFarmFile( $farm_name );
		open FI, "<$configdir/$farm_filename";
		my $first = "true";
		while ( $line = <FI> )
		{
			if ( $line ne "" && $first eq "true" )
			{
				$first = "false";
				my @line_a = split ( "\;", $line );
				my @line_b = split ( "\:", $line_a[2] );
				$output = $line_b[0];
			}
		}
		close FI;
	}

	return $output;
}

=begin nd
Function: getDatalinkFarmVip

	Returns farm vip, vport or vip:vport
	
Parameters:
	info - parameter to return: vip, for virtual ip; vipp, for virtual port or vipps, for vip:vipp
	farmname - Farm name

Returns:
	Scalar - return request parameter on success or -1 on failure
		
=cut
sub getDatalinkFarmVip    # ($info,$farm_name)
{
	my ( $info, $farm_name ) = @_;

	my $farm_filename = &getFarmFile( $farm_name );
	my $output        = -1;
	my $first         = "true";

	open FI, "<$configdir/$farm_filename";

	while ( my $line = <FI> )
	{
		if ( $line ne "" && $first eq "true" )
		{
			$first = "false";
			my @line_a = split ( "\;", $line );

			if ( $info eq "vip" )   { $output = $line_a[1]; }
			if ( $info eq "vipp" )  { $output = $line_a[2]; }
			if ( $info eq "vipps" ) { $output = "$line_a[1]\:$line_a[2]"; }
		}
	}
	close FI;

	return $output;
}

=begin nd
Function: setDatalinkFarmVirtualConf

	Set farm virtual IP and virtual PORT
	
Parameters:
	vip - virtual ip
	port - virtual port
	farmname - Farm name

Returns:
	Scalar - Error code: 0 on success or -1 on failure
		
=cut
sub setDatalinkFarmVirtualConf    # ($vip,$vip_port,$farm_name)
{
	my ( $vip, $vip_port, $farm_name ) = @_;

	require Tie::File;
	require Zevenet::Farm::Action;

	my $farm_filename = &getFarmFile( $farm_name );
	my $farm_state    = &getFarmStatus( $farm_name );
	my $stat          = -1;
	my $i             = 0;

	&runFarmStop( $farm_name, 'true' ) if $farm_state eq 'up';

	tie my @configfile, 'Tie::File', "$configdir\/$farm_filename";

	for my $line ( @configfile )
	{
		if ( $line =~ /^$farm_name\;/ )
		{
			my @args = split ( "\;", $line );
			$line = "$args[0]\;$vip\;$vip_port\;$args[3]\;$args[4]";
			splice @configfile, $i, $line;
			$stat = $?;
		}
		$i++;
	}
	untie @configfile;
	$stat = $?;

	&runFarmStart( $farm_name, 'true' ) if $farm_state eq 'up';

	return $stat;
}

1;
