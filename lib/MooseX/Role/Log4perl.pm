#
# MooseX::Log4perl
#
# Created On: Thu May 17 11:31:57 PDT 2007
# Created By: Adam Jacob, <adam@hjksolutions.com>
#
# Copyright 2007, HJK Solutions
#
# $Id$

package MooseX::Role::Log4perl;

use Moose::Role;
use Log::Log4perl;

has 'log4perl_config'         => ( is => 'rw', isa => 'Str' );
has '_moosex_log4perl_logger' => ( is => 'ro', isa => 'Object' );

sub _moosex_log4perl_init {
  my ( $self, $params ) = @_;

  unless ( Log::Log4perl->initialized ) {
    if ( exists( $params->{'log4perl_config'} ) ) {
      die "Cannot find " . $params->{'log4perl_config'}
        unless -f $params->{'log4perl_config'};
      Log::Log4perl::init( $params->{'log4perl_config'} );
    } else {
      my $conf = q(
log4perl.rootLogger=DEBUG, Screen
log4perl.appender.Screen=Log::Log4perl::Appender::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.stderr=0
log4perl.appender.Screen.layout.ConversionPattern=[%d] [%C (%L)] [%p] %m%n
            );
      Log::Log4perl::init( \$conf );
    }
  }
  $self->{'_moosex_log4perl_logger'} =
    Log::Log4perl::get_logger( $self->blessed );
}

sub log {
  my $self = shift;

  $self->_moosex_log4perl_init
    unless defined( $self->_moosex_log4perl_logger );
  return $self->_moosex_log4perl_logger;
}

sub logger {
  my $self    = shift;
  my $logname = shift;

  return Log::Log4perl->get_logger($logname);
}

1;

