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

sub index :Private {
  my ($self, $c) = @_;
  my $config = $c->model('Config');
  $c->stash->{domains} = $config->get_domains;
  $c->stash->{nodes} = {};
  $c->stash->{nodes_categories} = {};
  foreach my $domain (@{$c->stash->{domains}}) {
    $c->stash->{nodes}->{$domain} = $config->get_nodes($domain);
    foreach my $node (@{$c->stash->{nodes}->{$domain}}) {
      $c->stash->{nodes_categories}->{$domain}->{$node} = $config->get_graph_categories($domain, $node);
    }
  }
}

sub show :Path('') :Args(2) {
    my ( $self, $c, $domain, $node ) = @_;
    
    my $config = $c->model('Config');
    $c->stash->{graph_time} = $c->req->param('graph_time') || 'dayweek';
    $c->stash->{domain} = $domain;
    $c->stash->{node} = $node;
    $c->stash->{graph_categories} = $config->get_graph_categories($domain, $node);
    $c->stash->{graphs} = $config->get_graphs_by_category($domain, $node);
    $c->stash->{link_category} = 1;
    $c->stash->{link_graphs} = 1;
    $c->stash->{show_graph_info} = 0;
}

sub show_category :Path('') :Args(3) {
  my ($self, $c, $domain, $node, $category ) = @_;
  
  my $config = $c->model('Config');
  $c->stash->{graph_time} = $c->req->param('graph_time') || 'dayweek';
  $c->stash->{domain} = $domain;
  $c->stash->{node} = $node;
  $c->stash->{graph_categories} = [ $category ];
  $c->stash->{graphs} = $config->get_graphs_by_category($domain, $node, $category);
  $c->stash->{link_category} = 0;
  $c->stash->{link_graphs} = 1;
  $c->stash->{show_graph_info} = 0;
  if ($c->req->header('X-Requested-With') eq "XMLHttpRequest") {
    $c->stash->{xhr} = 1;
    $c->stash->{link_category} = 1;
    $c->stash->{template} = 'node/show_category_xhr.tt';
  } 
}

sub show_graph :Path('') :Args(4) {
  my ($self, $c, $domain, $node, $category, $graph ) = @_;
  
  my $config = $c->model('Config');
  $c->stash->{graph_time} = $c->req->param('graph_time') || 'dayweek';
  $c->stash->{domain} = $domain;
  $c->stash->{node} = $node;
  $c->stash->{graph_categories} = [ $category ];
  $c->stash->{graphs} = $config->get_graphs_by_category($domain, $node, $category, $graph);
  $c->stash->{link_category} = 1;
  $c->stash->{link_graphs} = 0;
  $c->stash->{show_graph_info} = 1;
  if ($c->req->header('X-Requested-With') eq "XMLHttpRequest") {
    $c->stash->{xhr} = 1;
    $c->stash->{link_graphs} = 1;
    $c->stash->{show_graph_info} = 0;
    $c->stash->{template} = 'node/show_graph_xhr.tt';
  }
}


=head1 AUTHOR

Adam Jacob

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
