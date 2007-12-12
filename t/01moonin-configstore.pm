#
# 01moonin-configstore.pm
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

use Moonin::Config::Store;

my $cfg =
  Moonin::Config::Store->new( directory => "$FindBin::Bin/out/db" );

is(ref($cfg), 'Moonin::Config::Store', "New returns a Moonin::Config::Store object");
ok($cfg->set("one", 'two'), "Set a value");
is($cfg->get("one"), 'two', "Got the value back");
is($cfg->exists("one"), 1, "Value exists in cache");
is($cfg->exists("two"), 0, "Value does not exist in cache");
ok($cfg->remove("one"), "Removed one");
is($cfg->exists("one"), 0, "Removed value does not exist in cache");
$cfg->set("one", 'two');
$cfg->clear();
is($cfg->exists("one"), 0, "Clear wiped out all values");
