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

use lib ( "$FindBin::Bin/lib", "$FindBin::Bin/../lib" );

use Moonin::Config;

my $cfg =
  Moonin::Config->new( config_file => "$FindBin::Bin/data/munin.conf" );

is(ref($cfg), 'Moonin::Config', "New returns a Moonin::Config object");
is(ref($cfg->config), 'HASH', "config returns a hashref");
is($cfg->domains, $cfg->config->{domains}, "domains returns domains");
my $dhash = { 'monkey => 1 '};

is($cfg->domains($dhash), $dhash, "setting domains returns same settings");

my $oldconfig = Moonin::Config->new( config_file => "$FindBin::Bin/data/datafile");
is(ref($cfg->config), 'HASH', "oldconfig returns a hashref");

eval {
    my $dcfg = Moonin::Config->new( config_file => "/tmp/dumpy.dumperton");
};
ok(Exception::Class->caught("Moonin::Exception::Config"), "Caught config exception on no config loaded.");

is($cfg->tmpldir, "/etc/munin/templates", "Meta-Methods added correctly");
