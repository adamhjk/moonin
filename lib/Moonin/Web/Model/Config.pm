package Moonin::Web::Model::Config;

use strict;
use warnings;
use base 'Catalyst::Model::Adaptor';

__PACKAGE__->config( 
  class => "Moonin::Config",
);


=head1 NAME

Moonin::Web::Model::Config - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

Adam Jacob

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
