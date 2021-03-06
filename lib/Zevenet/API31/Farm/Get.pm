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
use Zevenet::Config;
use Zevenet::Farm::Core;
use Zevenet::Farm::Base;

#GET /farms
sub farms # ()
{
	require Zevenet::Farm::Base;

	my @out;
	my @files = &getFarmList();

	foreach my $file ( @files )
	{
		my $name   = &getFarmName( $file );
		my $type   = &getFarmType( $name );
		my $status = &getFarmVipStatus( $name );
		my $vip    = &getFarmVip( 'vip', $name );
		my $port   = &getFarmVip( 'vipp', $name );

		push @out,
		  {
			farmname => $name,
			profile  => $type,
			status   => $status,
			vip      => $vip,
			vport    => $port
		  };
	}

	my $body = {
				description => "List farms",
				params      => \@out,
	};

	&httpResponse({ code => 200, body => $body });
}

# GET /farms/LSLBFARM
sub farms_lslb # ()
{
	require Zevenet::Farm::Base;
	require Zevenet::Farm::HTTP;
	require Zevenet::Farm::L4xNAT;

	my @out;
	my @files = &getFarmList();

	foreach my $file ( @files )
	{
		my $name   = &getFarmName( $file );
		my $type   = &getFarmType( $name );
		next unless $type =~ /^(?:https?|l4xnat)$/;
		my $status = &getFarmVipStatus( $name );
		my $vip    = &getFarmVip( 'vip', $name );
		my $port   = &getFarmVip( 'vipp', $name );

		push @out,
		  {
			farmname => $name,
			profile  => $type,
			status   => $status,
			vip      => $vip,
			vport    => $port
		  };
	}

	my $body = {
				description => "List LSLB farms",
				params      => \@out,
	};

	&httpResponse({ code => 200, body => $body });
}

# GET /farms/DATALINKFARM
sub farms_dslb # ()
{
	require Zevenet::Farm::Base;
	require Zevenet::Farm::Datalink;

	my @out;
	my @files = &getFarmList();

	foreach my $file ( @files )
	{
		my $name   = &getFarmName( $file );
		my $type   = &getFarmType( $name );
		next unless $type eq 'datalink';
		my $status = &getFarmVipStatus( $name );
		my $vip    = &getFarmVip( 'vip', $name );
		my $iface  = &getFarmVip( 'vipp', $name );

		push @out,
		  {
			farmname => $name,
			status   => $status,
			vip      => $vip,
			interface => $iface
		  };
	}

	my $body = {
				description => "List DSLB farms",
				params      => \@out,
	};

	&httpResponse({ code => 200, body => $body });
}

#GET /farms/<name>
sub farms_name # ( $farmname )
{
	my $farmname = shift;

	my $desc = "Show farm $farmname";

	# Check if the farm exists
	if ( &getFarmFile( $farmname ) == -1 )
	{
		my $msg = "Farm not found.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $type = &getFarmType( $farmname );

	if ( $type =~ /https?/ )
	{
		require Zevenet::API31::Farm::Get::HTTP;
		&farms_name_http( $farmname );
	}
	if ( $type eq 'l4xnat' )
	{
		require Zevenet::API31::Farm::Get::L4xNAT;
		&farms_name_l4( $farmname );
	}
	if ( $type eq 'datalink' )
	{
		require Zevenet::API31::Farm::Get::Datalink;
		&farms_name_datalink( $farmname );
	}
	if ( $type eq 'gslb' )
	{
		if ( eval{ require Zevenet::API31::Farm::Get::GSLB; } )
		{
			&farms_name_gslb( $farmname );
		}
	}
}

1;
