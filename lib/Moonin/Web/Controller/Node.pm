package Moonin::Web::Controller::Node;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dump qw(dump);

=head1 NAME

Moonin::Web::Controller::Node - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub show :Local :Args(2) {
    my ( $self, $c, $domain, $node ) = @_;
    
    my $config = $c->model('Config');
    $c->stash->{domain} = $domain;
    $c->stash->{node} = $node;
    $c->stash->{graph_categories} = $config->get_graph_categories($domain, $node);
    $c->stash->{graphs} = $config->get_graphs_by_category($domain, $node);
    $c->log->debug(dump($c->stash));
}


=head1 AUTHOR

Adam Jacob

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
