#
# 04moonin-graph.pm
#
# Copyright (C) 2007 Adam Jacob
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; version 2 dated June,
# 1991.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

use strict;
use warnings;
use Test::More qw(no_plan);
use FindBin;
use Exception::Class;
use Data::Dump qw(dump);
use Log::Log4perl;

            my $conf = q(
log4perl.rootLogger=DEBUG, Screen
log4perl.appender.Screen=Log::Log4perl::Appender::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.stderr=0
log4perl.appender.Screen.layout.ConversionPattern=[%d] [%C (%L)] [%p] %m%n
            );
            Log::Log4perl::init( \$conf );

use lib ( "$FindBin::Bin/lib", "$FindBin::Bin/../lib" );

use Moonin::Config;
use Moonin::Node;
use Moonin::Graph;

my $cfg =
  Moonin::Config->new( config_file => "$FindBin::Bin/data/munin-test.conf" );
my $mn = Moonin::Node->new(
  name   => 'ops1prod.sfo.v2green.com',
  domain => 'sfo.v2green.com',
  config => $cfg
);
isa_ok( $mn, 'Moonin::Node' );

my $graph = Moonin::Graph->new(
  node => $mn
);

$graph->process("cpu");
$graph->process("cpu", "day");
