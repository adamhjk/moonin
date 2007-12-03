package Moonin::Web::Model::Node;

use strict;
use warnings;
use base 'Catalyst::Model';
use Moonin::Node;

__PACKAGE__->config( 
  class => "Moonin::Node"
);

sub ACCEPT_CONTEXT {
  my ($self, $c, $args) = @_;
  return Moonin::Node->new(
    config => $c->model("Config"), 
    domain => $args->[0],
    node   => $args->[1]
  );
}

=head1 NAME

Moonin::Web::Model::Node - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

Adam Jacob

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
