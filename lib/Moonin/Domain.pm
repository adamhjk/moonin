#
# Moonin::Domains
#
# Portions of this file taken from Munin
#   Copyright (C) 2003-2004 Jimmy Olsen, Audun Ytterdal
#
#
# Created On: Thu May 17 16:04:12 PDT 2007
# Created By: Adam Jacob, <adam@hjksolutions.com>
#
# Copyright 2007, HJK Solutions
#
# $Id$

package Moonin::Domain;

use Moose;
use Config::Any;
use Moonin::Node;
use Data::Dump qw(dump);

with 'MooseX::Role::Log4perl', 'Moonin::Role::Exception';

has 'name'    => ( is => 'rw', isa => 'Str', required => 1 );
has 'domain'  => ( is => 'ro', isa => 'HashRef', required => 0 );
has 'config'  => ( is => 'rw', isa => 'Object', required => 1 );

sub BUILD {
  my $self = shift;
  
  $self->{domain} = $self->config->domain->{$self->name};
}

sub process {
  my $self = shift;
  $self->log->debug("Processing domain " . $self->name);
  for my $key ( keys %{ $self->domain->{node} } ) {
    $self->log->debug("Processing node $key");
    my $node = Moonin::Node->new( 
      domain => $self->name,
      node   => $key,
      config => $self->config
    );
    $node->process;
  }
}

1;
