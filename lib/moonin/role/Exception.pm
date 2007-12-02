#
# Moonin::Role::Exception
#
# Created On: Thu May 17 13:59:11 PDT 2007
# Created By: Adam Jacob, <adam@hjksolutions.com>
#
# Copyright 2007, HJK Solutions
#
# $Id$

package Moonin::Role::Exception;

use Moose::Role;
use Moonin::Exception;

sub log_exception {
  my $self      = shift;
  my $exception = shift;
  my $message   = shift;

  my $logger = $self->logger( $self->blessed );
  $logger->error($message);
  my $class = "Moonin::Exception::$exception";
  $class->throw( "Fatal Exception: " . $message . "\n" );
  return 1;
}

1;

