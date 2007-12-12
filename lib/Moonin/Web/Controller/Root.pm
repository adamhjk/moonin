package Moonin::Web::Controller::Root;

use strict;
use warnings;
use base 'Catalyst::Controller';

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

=head1 NAME

Moonin::Web::Controller::Root - Root Controller for Moonin::Web

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=cut

=head2 default

=cut

sub default : Private {
  my ( $self, $c ) = @_;

  # Hello World
  $c->res->status('404');
  $c->res->body("Sorry, 404 not found.");
}

sub index : Private {
  my ( $self, $c ) = @_;

  $c->forward("/node/index");
}

=head2 end

Attempt to render a view, if needed.

=cut 

sub end : ActionClass('RenderView') {
}

=head1 AUTHOR

Adam Jacob

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
