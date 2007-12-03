#
# Moonin::Config::Store
#
#
# Created On: Thu May 17 16:04:12 PDT 2007
# Created By: Adam Jacob, <adam@hjksolutions.com>
#
# Copyright 2007, HJK Solutions
#
# $Id$
#

package Moonin::Config::Store;

use Moose;
use Data::Dump qw(dump);
use DBM::Deep;

with 'MooseX::Role::Log4perl', 'Moonin::Role::Exception';

has 'file' => ( is => 'rw', isa => 'Str', required => 1 );
has 'dbm' => ( is => 'ro', isa => 'Object', required => 0 );

sub BUILD {
  my $self = shift;
  
  $self->{dbm} = DBM::Deep->new(
    file => $self->file,
    locking => 1,
    autoflush => 1
  );
  $self;
}

sub put {
  my $self = shift;
  $self->dbm->put(@_);
}

sub get {
  my $self = shift;
  $self->dbm->get(@_);
}

sub exists {
  my $self = shift;
  $self->dbm->exists(@_);
}

sub delete {
  my $self = shift;
  $self->dbm->delete(@_);
}

sub clear {
  my $self = shift;
  $self->dbm->clear(@_);
}

sub lock {
  my $self = shift;
  $self->dbm->lock(@_);
}

sub unlock {
  my $self = shift;
  $self->dbm->unlock(@_);
}

sub optimize {
  my $self = shift;
  $self->dbm->optimize(@_);
}

sub begin_work {
  my $self = shift;
  $self->dbm->begin_work(@_);
}

sub commit {
  my $self = shift;
  $self->dbm->commit(@_);
}

sub rollback {
  my $self = shift;
  $self->dbm->rollback(@_);
}

sub log_contents {
  my $self = shift;
  $self->log->warn(dump($self->{dbm}));
}

1;