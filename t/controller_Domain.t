use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'Moonin::Web' }
BEGIN { use_ok 'Moonin::Web::Controller::Domain' }

ok( request('/domain')->is_success, 'Request should succeed' );


