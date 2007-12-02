#
# 01moonin-config.pm
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

use lib ( "$FindBin::Bin/lib", "$FindBin::Bin/../lib" );

use Moonin::Config;
use Moonin::Domain;

my $cfg = Moonin::Config->new( config_file => "$FindBin::Bin/data/munin.conf" );
my $md = Moonin::Domain->new( 
  name => 'test.hjksolutions.com',
  config => $cfg
);
isa_ok($md, 'Moonin::Domain');
is($md->domain, $cfg->domain('test.hjksolutions.com'), "Domain config matches");


