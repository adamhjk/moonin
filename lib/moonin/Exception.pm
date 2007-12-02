#
# Moonin::Exception
#
# Created On: Thu May 17 13:55:52 PDT 2007
# Created By: Adam Jacob, <adam@hjksolutions.com>
#
# Copyright 2007, HJK Solutions
#
# $Id$

package Moonin::Exception;

use strict;
use warnings;

use Exception::Class (

  'Moonin::Exception::Generic' =>
    { description => 'Had a problem doing something... random', },

  'Moonin::Exception::InvalidArgument' => {
    description => 'Had a problem with my arguments',
    isa         => 'Moonin::Exception::Generic',
  },

  'Moonin::Exception::Config' => {
    description => 'Had a trouble with a configuration file!',
    isa         => 'Moonin::Exception::Generic',
  },
  
  'Moonin::Exception::Timeout' => {
    description => 'Something took too long!',
    isa         => 'Moonin::Exception::Generic',
  },

);

1;

