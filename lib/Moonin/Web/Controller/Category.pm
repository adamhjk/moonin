package Moonin::Web::Controller::Category;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dump qw(dump);

=head1 NAME

Moonin::Web::Controller::Service - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

sub index : Private {
  my ( $self, $c ) = @_;

  my $config = $c->model('Config');
  $c->stash->{categories} = $config->get_all_graph_categories;
  $c->stash->{graph_categories} = $config->get_all_graphs_by_category;
  $c->log->debug(dump($c->stash));
}

sub show : Path('') :Args(1) {
  my ($self, $c, $category) = @_;
  my $config = $c->model('Config');
  $c->stash->{graph_time} = $c->req->param('graph_time') || 'dayweek';
  $c->stash->{category} = $category;
  $c->stash->{graph_categories} = $config->get_all_graph_categories($category);
  $c->stash->{graphs} = $config->get_all_graphs_by_category($category);
  $c->stash->{nodes} = $config->get_all_nodes_by_graph();
  $c->stash->{link_category} = 1;
  $c->stash->{link_graphs} = 1;
  $c->stash->{show_graph_info} = 0;
  $c->log->debug("ass monkey");
  $c->log->debug(dump($c->stash->{nodes}));
}

=head1 AUTHOR

Adam Jacob

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
