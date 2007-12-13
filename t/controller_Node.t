use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'Moonin::Web' }
BEGIN { use_ok 'Moonin::Web::Controller::Node' }

ok( request('/node')->is_success, 'Request should succeed' );
