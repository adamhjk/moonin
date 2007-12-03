package Moonin::Web::Model::Graph;

use strict;
use warnings;
use base 'Catalyst::Model';
use Moonin::Node;
use Moonin::Graph;

sub ACCEPT_CONTEXT {
  my ($self, $c, $domain, $name) = @_;
  my $node = Moonin::Node->new(
    config => $c->model("Config"), 
    domain => $domain,
    name   => $name
  );
  return Moonin::Graph->new(
    node => $node
  );
}

1;