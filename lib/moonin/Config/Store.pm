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
use Cache::FileCache;

with 'MooseX::Role::Log4perl', 'Moonin::Role::Exception';

has 'directory' => ( is => 'rw', isa => 'Str', required => 1 );
has 'cache' => ( is => 'ro', isa => 'Object', required => 0 );

sub BUILD {
  my $self = shift;
  
  $self->{cache} = Cache::FileCache->new({
    namespace => "Moonin",
    default_expires_in => $Cache::FileCache::EXPIRES_NEVER,
    cache_root => $self->directory,
  }
  );
  
  $self;
}

sub set {
  my $self = shift;
  $self->cache->set(@_);
  return 1;
}

sub get {
  my $self = shift;
  $self->cache->get(@_);
}

sub exists {
  my $self = shift;
  my $key = shift;
  eval { $self->cache->get($key) }
  my $e;
  if ($e = Exception::Class->caught()) {
    return 0;
  } else {
    return 1;
  }
}

sub remove {
  my $self = shift;
  $self->cache->remove(@_);
}

sub clear {
  my $self = shift;
  $self->cache->clear;
}

sub keys {
  my $self = shift;
  $self->cache->get_keys;
}

sub log_contents {
  my $self = shift;
  $self->log->warn(dump($self->{cache}));
}

1;