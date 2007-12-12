package Moonin::Web::Controller::Domain;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

Moonin::Web::Controller::Domain - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

sub show : Path('') : Args(1) {
  my ( $self, $c, $domain ) = @_;

  my $config = $c->model('Config');
  $c->stash->{domains}          = [$domain];
  $c->stash->{nodes}            = {};
  $c->stash->{nodes_categories} = {};
  foreach my $domain ( @{ $c->stash->{domains} } ) {
    $c->stash->{nodes}->{$domain} = $config->get_nodes($domain);
    foreach my $node ( @{ $c->stash->{nodes}->{$domain} } ) {
      $c->stash->{nodes_categories}->{$domain}->{$node} =
        $config->get_graph_categories( $domain, $node );
    }
  }
}

=head1 AUTHOR

Adam Jacob

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
