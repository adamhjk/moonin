#
# Moonin::Domains
#
# Much of this file taken almost entirely from Munin
#   Copyright (C) 2003-2004 Jimmy Olsen, Audun Ytterdal
#
# Created On: Thu May 17 16:04:12 PDT 2007
# Created By: Adam Jacob, <adam@hjksolutions.com>
#
# Copyright 2007, HJK Solutions
#
# $Id$

package Moonin::Node;

use Moose;
use Config::Any;
use Data::Dump qw(dump);
use Time::HiRes;
use RRDs;
use IO::Socket;
use POSIX qw(strftime);
use POSIX ":sys_wait_h";

with 'MooseX::Role::Log4perl', 'Moonin::Role::Exception';

has 'name'        => ( is => 'rw', isa => 'Str',     required => 1 );
has 'domain'      => ( is => 'rw', isa => 'Str',     required => 1 );
has 'config'      => ( is => 'rw', isa => 'Object',  required => 1 );
has 'node_config' => ( is => 'ro', isa => 'HashRef', required => 0 );
has 'timeout' => ( is => 'rw', isa => 'Int', required => 1, default => 180 );
has 'limit_services' => ( is => 'rw', required => 0, default => undef );
has 'copy_fields' => (
  is       => 'rw',
  required => 0,
  defualt =>
    sub { [ "label", "draw", "type", "rrdfile", "fieldname", "info" ] }
);

sub BUILD {
  my $self = shift;

  $self->{node_config} =
    $self->config->domain->{ $self->domain }->{node}->{ $self->name };
}

sub process {
  my $self    = shift;
  my $domain  = $self->domain;
  my $name    = $self->name;
  my $node    = $self->node_config;
  my $config  = $self->config;
  my $oldnode = $self->config->store->get("node-$domain-$name");

  $self->log->debug( "Processing node " . $self->name );

  return if ( exists( $node->{fetch_data} ) and !$node->{fetch_data} );
  return if ( exists( $node->{update} ) and $node->{update} ne "yes" );
  unless ( $node->{address} ) {
    $self->log_exception( "Config", "No address defined for node: $name" );
  }

  my $socket;

  if ( $self->config->get( "local_address", undef, $domain, $node ) ) {
    $socket = new IO::Socket::INET(
      'PeerAddr' => "$node->{address}:"
        . (
             $node->{port}
          || $self->config->domain->{$domain}->{port}
          || $self->config->port
          || "4949"
        ),
      'LocalAddr' =>
        $self->config->get( "local_address", undef, $domain, $node ),
      'Proto'   => "tcp",
      "Timeout" => $self->timeout
    );
  } else {
    $socket = new IO::Socket::INET(
      'PeerAddr' => "$node->{address}:"
        . (
             $node->{port}
          || $self->config->domain->{$domain}->{port}
          || $self->config->port
          || "4949"
        ),
      'Proto'   => "tcp",
      "Timeout" => $self->timeout
    );
  }
  my $err = ( $socket ? "" : $! );

  if ( !$socket ) {
    $self->log->error(
"Could not connect to $name($node->{address}): $err\nAttempting to use old configuration"
    );

    # If we can't reach the client. Using old Configuration.
    if ( ref $oldnode ) {
      $self->config->domain->{$domain}->{node}->{$name} = $oldnode;
    }
  } else {
    next
      unless ( $self->configure($socket) );
    $self->fetch($socket);

    #		Net::SSLeay::free ($tls) if ($tls); # Shut down TLS
    close $socket;
  }

}

sub fetch {
  my ( $self, $socket ) = @_;
  my $domain = $self->domain;
  my $name   = $self->name;
  my $node   = $self->node_config;
  my $config = $self->config;

  my $nodefetch_time = Time::HiRes::time;
  $self->log->debug("Fetching node: $name");
  for my $service ( keys %{ $node->{client} } ) {
    my $servicefetch_time = Time::HiRes::time;
    $self->log->debug("Fetching service: $name->$service");
    next
      if ( exists( $node->{client}->{$service}->{fetch_data} )
      and $node->{client}->{$service}->{fetch_data} == 0 );
    next
      if ( exists( $node->{client}->{$service}->{update} )
      and $node->{client}->{$service}->{update} ne "yes" );
    next
      if ( $self->limit_services
      and !grep ( /^$service$/, @{ $self->limit_services } ) );
    my $realservname =
      ( $node->{client}->{$service}->{realservname} || $service );
    delete $node->{client}->{$service}->{realservname}
      if exists $node->{client}->{$service}->{realservname};
    $self->_write_socket_single( $socket, "fetch $realservname\n" );
    my @lines = $self->_read_socket($socket);
    return 0 unless $socket;
    my $fields = {};

    for (@lines) {
      next unless defined $_;
      if (/\# timeout/) {
        $self->log->warning(
          "Client reported timeout in fetching of $service");
      } elsif (/(\w+)\.value\s+(\S+)\s*(\#.*)?$/) {
        my $key     = $1;
        my $value   = $2;
        my $comment = $3;

        if ( $value =~ /\d[Ee]([+-]?\d+)$/ ) {

          # Looks like scientific format.  RRDtool does not
          # like it so we convert it.
          my $magnitude = $1;
          if ( $magnitude < 0 ) {

            # Preserve at least 4 significant digits
            $magnitude = abs($magnitude) + 4;
            $value = sprintf( "%.%magnitudef", $value );
          } else {
            $value = sprintf( "%.4f", $value );
          }
        }

        $key = $self->_sanitise_fieldname( $key, $fields );
        if ( exists $node->{client}->{$service}->{ $key . ".label" } ) {
          my $fname = $config->dbdir . "/$domain/$name-$service-$key-"
            . lc substr(
            ( $node->{client}->{$service}->{ $key . ".type" } || "GAUGE" ),
            0, 1 )
            . ".rrd";

          $self->log->debug("Updating $fname with $value");
          RRDs::update( "$fname", "N:$value" );
          if ( my $ERROR = RRDs::error ) {
            $self->log->error("In RRD: unable to update $fname: $ERROR");
          }
        } else {
          $self->log->error(
"Unable to update $domain -> $name -> $service -> $key: No such field (no \"label\" field defined when running plugin with \"config\")."
          );
        }
      } elsif (/(\w+)\.extinfo\s+(.+)/) {
        $config->domain->{$domain}->{node}->{$name}->{client}->{$service}
          ->{ $1 . ".extinfo" } = $2;
      }
    }
    $servicefetch_time =
      sprintf( "%.2f", ( Time::HiRes::time - $servicefetch_time ) );
    $self->log->debug(
      "Fetched service: $name -> $service ($servicefetch_time sec)");
    $self->config->store->dbm->{FS}->{$domain}->{$name}->{$service} =
      $servicefetch_time;
  }
  $nodefetch_time =
    sprintf( "%.2f", ( Time::HiRes::time - $nodefetch_time ) );
  $self->log->debug("Fetched node: $name ($nodefetch_time sec)");
  $self->config->store->dbm->{FN}->{$domain}->{$name} = $nodefetch_time;

  return 1;
}

sub configure {
  my ( $self, $socket ) = @_;
  my $domain  = $self->domain;
  my $name    = $self->name;
  my $node    = $self->node_config;
  my $oldnode = $self->config->store->get("node-$domain-$name");

  my $clientdomain = $self->_read_socket_single($socket);
  my $fetchdomain;
  chomp($clientdomain) if $clientdomain;
  if ( !$clientdomain ) {
    $self->log_exception( "InvalidArgument",
      "Got unknown reply from client \"$domain\" -> \"name\" skipping" );
  }
  $clientdomain =~ s/\#.*(?:lrrd|munin) (?:client|node) at //;
  if ( exists $node->{'use_node_name'}
    and $node->{'use_node_name'} =~ /^\s*y(?:es)\s*$/i ) {
    $fetchdomain = $clientdomain;
  } elsif ( exists $node->{'use_default_name'}
    and $node->{'use_default_name'} =~ /^\s*y(?:es)\s*$/i ) {
    $fetchdomain = $clientdomain;
  } else {
    $fetchdomain = $name;
  }
  my $nodeconf_time = Time::HiRes::time;

  $self->log->debug("Configuring node: $name");
  my @services;
  eval {
    local $SIG{ALRM} =
      sub { die "Could not run list on $name ($fetchdomain): $!\n" };
    alarm 5;    # Should be enough to check the list
    $self->_write_socket_single( $socket, "list $fetchdomain\n" );
    my $list = $self->_read_socket_single($socket);
    exit 1 unless defined $list;
    chomp $list;
    @services = split / /, $list;
    alarm 0;
  };
  if ($@) {
    die unless ( $@ =~ m/Could not run list/ );
    $self->log->error(
"Could not get list from $node->{address}: $!\nAttempting to use old configuration"
    );
    if ( ref $oldnode ) {
      $self->config->domain->{$domain}->{node}->{$name} = $oldnode;
    }
    @services = [];
  }

  for my $service (@services) {
    my $servname = $service;
    my $fields   = {};
    $servname =~ s/\W/_/g;
    next
      if ( exists( $node->{client}->{$servname}->{fetch_data} )
      and $node->{client}->{$servname}->{fetch_data} == 0 );
    next
      if ( exists( $node->{client}->{$servname}->{update} )
      and $node->{client}->{$servname}->{update} ne "yes" );
    next
      if ( $self->limit_services
      and !grep ( /^$servname$/, @{ $self->limit_services } ) );
    my @graph_order = (
      exists $node->{client}->{$servname}->{graph_order}
      ? split( /\s+/, $node->{client}->{$servname}->{graph_order} )
      : ()
    );
    my $serviceconf_time = Time::HiRes::time;

    if ( $servname ne $service ) {
      $node->{client}->{$servname}->{realservname} = $service;
    }
    $self->log->debug("Configuring service: $name->$servname");
    $self->_write_socket_single( $socket, "config $service\n" );
    my @lines = $self->_read_socket($socket);
    return unless $socket;
    next   unless (@lines);
    for (@lines) {
      if (/\# timeout/) {
        $self->log->warning(
          "Client reported timeout in configuration of $servname");
        if ( $oldnode->{client}->{$servname} ) {
          $self->log->warning("Attempting to use old configuration");
          $self->config->domain->{$domain}->{node}->{$name}->{client}
            ->{$servname} = $oldnode->{client}->{$servname};
        } else {
          $self->log->error("Skipping configuration of $servname");
          delete $node->{client}->{$servname};
        }
      } elsif (/^(\w+)\.(\w+)\s+(.+)/) {
        my ( $client, $type, $value ) = ( $1, $2, $3 );
        $client = $self->_sanitise_fieldname( $client, $fields );
        if ( ($type) and ( $type eq "label" ) ) {
          $value =~ s/\\/_/g;    # Sanitise labels
        }
        $node->{client}->{$servname}->{ $client . "." . $type } = "$value";
        $self->log->debug("config: $name->$client.$type = $value");
        if ( ($type) and ( $type eq "label" ) ) {
          push( @graph_order, $client )
            unless grep ( /^$client$/, @graph_order );
        }
      } elsif (/(^[^\s\#]+)\s+(.+)/) {
        my ($keyword) = $1;
        my ($value)   = $2;
        $node->{client}->{$servname}->{$keyword} = $value;
        $self->log->debug("config: $keyword = $value");
        if ( $keyword eq "graph_order" ) {
          @graph_order =
            split( /\s+/, $node->{client}->{$servname}->{graph_order} );
        }
      }
    }
    for my $subservice ( keys %{ $node->{client}->{$servname} } ) {
      my ( $client, $type ) = split /\./, $subservice;
      my ($value) = $node->{client}->{$servname}->{$subservice};
      if ( ($type) and ( $type eq "label" ) ) {
        my $fname = $self->config->dbdir . "/$domain/$name-$servname-$client-"
          . lc substr(
          ( $node->{client}->{$servname}->{"$client.type"} || "GAUGE" ),
          0, 1 )
          . ".rrd";
        if ( !-f "$fname" ) {
          $self->log->info("creating rrd-file for $servname->$subservice");
          mkdir $self->config->dbdir . "/$domain/", 0777;
          my @args = (
            "$fname",
            "DS:42:"
              . ( $node->{client}->{$servname}->{"$client.type"} || "GAUGE" )
              . ":600:"
              . (
              defined $node->{client}->{$servname}->{"$client.min"}
              ? $node->{client}->{$servname}->{"$client.min"}
              : "U"
              )
              . ":"
              . ( $node->{client}->{$servname}->{"$client.max"} || "U" )
          );
          my $resolution =
            $self->config->get( "graph_data_size", "normal", $domain, $node,
            $servname );
          if ( $resolution eq "normal" ) {
            push(
              @args,
              "RRA:AVERAGE:0.5:1:576",      # resolution 5 minutes
              "RRA:MIN:0.5:1:576",
              "RRA:MAX:0.5:1:576",
              "RRA:AVERAGE:0.5:6:432",      # 9 days, resolution 30 minutes
              "RRA:MIN:0.5:6:432",
              "RRA:MAX:0.5:6:432",
              "RRA:AVERAGE:0.5:24:540",     # 45 days, resolution 2 hours
              "RRA:MIN:0.5:24:540",
              "RRA:MAX:0.5:24:540",
              "RRA:AVERAGE:0.5:288:450",    # 450 days, resolution 1 day
              "RRA:MIN:0.5:288:450",
              "RRA:MAX:0.5:288:450"
            );
          } elsif ( $resolution eq "huge" ) {
            push( @args, "RRA:AVERAGE:0.5:1:115200" )
              ;    # resolution 5 minutes, for 400 days
            push( @args, "RRA:MIN:0.5:1:115200" );    # Three times? ARGH!
            push( @args, "RRA:MAX:0.5:1:115200" );    # Three times? ARGH!
          }
          RRDs::create @args;
          if ( my $ERROR = RRDs::error ) {
            $self->log->error("In RRD: unable to create \"$fname\": $ERROR");
          }
        }
      }
      $node->{client}->{$servname}->{graph_order} = join( ' ', @graph_order );
    }

    $serviceconf_time =
      sprintf( "%.2f", ( Time::HiRes::time - $serviceconf_time ) );
    $self->config->store->dbm->{'CS'}->{$domain}->{$name}->{$servname} =
      $serviceconf_time;
    $self->log->debug(
      "Configured service: $name -> $servname ($serviceconf_time sec)");
  }
  $self->config->store->dbm->{node}->{$domain}->{$name} = $node;
  $nodeconf_time = sprintf( "%.2f", ( Time::HiRes::time - $nodeconf_time ) );
  $self->config->store->dbm->{'CN'}->{$domain}->{$name} = $nodeconf_time;
  return 0 unless $socket;
  $self->log->debug("Configured node: $name ($nodeconf_time sec)");
  return 1;
}

sub get_node_config {
  my $self = shift;
  return $self->config->store->dbm->{node}->{ $self->domain }
    ->{ $self->name };
}

sub get_field_order {
  my $self    = shift;
  my $service = shift;
  my $node    = $self->get_node_config;
  my $config  = $self->config;
  my $domain  = $self->domain;
  my $result  = [];

  if ( $node->{client}->{$service}->{graph_sources} ) {
    foreach
      my $gs ( split /\s+/, $node->{client}->{$service}->{'graph_sources'} ) {
      push( @$result, "-" . $gs );
    }
  }
  if ( $node->{client}->{$service}->{graph_order} ) {
    push( @$result,
      split /\s+/, $node->{client}->{$service}->{'graph_order'} );
  }

  for my $key ( keys %{ $node->{client}->{$service} } ) {
    my ( $client, $type ) = "";
    ( $client, $type ) = split /\./, $key;
    if ( defined $type and $type eq "label" ) {
      push @$result, $client if !grep /^\Q$client\E(?:=|$)/, @$result;
    }
  }
  $self->log->debug( "Field order for $service: " . dump($result) );
  return $result;
}

sub get_max_label_length {
  my $self    = shift;
  my $node    = $self->get_node_config;
  my $service = shift;
  my $order   = shift;
  my $result  = 0;

  for my $field (@$order) {
    my $path = undef;
    ( my $f = $field ) =~ s/=.+//;
    next
      if (exists $node->{client}->{$service}->{ $f . ".process" }
      and $node->{client}->{$service}->{ $f . ".process" }
      and $node->{client}->{$service}->{ $f . ".process" } ne "yes" );
    next if ( exists $node->{client}->{$service}->{ $f . ".skipdraw" } );
    next
      unless ( !exists $node->{client}->{$service}->{ $f . ".graph" }
      or !$node->{client}->{$service}->{ $f . ".graph" }
      or $node->{client}->{$service}->{ $f . ".graph" } eq "yes" );
    if ( $result <
      length( $node->{client}->{$service}->{ $f . ".label" } || $f ) ) {
      $result =
        length( $node->{client}->{$service}->{ $f . ".label" } || $f );
    }
    if ( exists $node->{client}->{$service}->{graph_total}
      and length $node->{client}->{$service}->{graph_total} > $result ) {
      $result = length $node->{client}->{$service}->{graph_total};
    }
  }
  return $result;
}

sub process_field {
  my $self    = shift;
  my $service = shift;
  my $field   = shift;
  my $node    = $self->get_node_config;
  return ( $self->get_bool_val( $service, $field . ".process", 1 ) );
}

sub get_bool_val {
  my $self       = shift;
  my $service    = shift;
  my $field_name = shift;
  my $default    = shift;
  my $node       = $self->get_node_config;
  my $field      = $node->{client}->{$service}->{$field_name};

  if ( !defined $field ) {
    if ( !defined $default ) {
      return 0;
    } else {
      return $default;
    }
  }

  if ( $field =~ /^yes$/i
    or $field =~ /^true$/i
    or $field =~ /^on$/i
    or $field =~ /^enable$/i
    or $field =~ /^enabled$/i ) {
    return 1;
  } elsif ( $field =~ /^no$/i
    or $field =~ /^false$/i
    or $field =~ /^off$/i
    or $field =~ /^disable$/i
    or $field =~ /^disabled$/i ) {
    return 0;
  } elsif ( $field !~ /\D/ ) {
    return $field;
  } else {
    return undef;
  }
}

sub get_stack_command {
  my $self    = shift;
  my $service = shift;
  my $field   = shift;
  my $node    = $self->get_node_config;

  if ( defined $node->{client}->{$service}->{ $field . ".special_stack" } ) {
    return $node->{client}->{$service}->{ $field . ".special_stack" };
  } elsif ( defined $node->{client}->{$service}->{ $field . ".stack" } ) {
    return $node->{client}->{$service}->{ $field . ".stack" };
  }

  return undef;
}

sub get_sum_command {
  my $self    = shift;
  my $service = shift;
  my $field   = shift;
  my $node    = $self->get_node_config;

  if ( defined $node->{client}->{$service}->{ $field . ".special_sum" } ) {
    return $node->{client}->{$service}->{ $field . ".special_sum" };
  } elsif ( defined $node->{client}->{$service}->{ $field . ".sum" } ) {
    return $node->{client}->{$service}->{ $field . ".sum" };
  }

  return undef;
}

sub get_filename {
  my $self    = shift;
  my $config  = $self->config;
  my $domain  = $self->domain;
  my $node    = $self->get_node_config;
  my $service = shift;
  my $field   = shift;

  return (
    $config->dbdir . "/$domain/" . $self->name . "-$service-$field-"
      . lc substr(
      ( $node->{client}->{$service}->{ $field . ".type" } || "GAUGE" ),
      0, 1 )
      . ".rrd"
  );

}

sub get_rrd_filename {
  my $self    = shift;
  my $node    = $self->get_node_config;
  my $config  = $self->config;
  my $domain  = $self->domain;
  my $name    = $self->name;
  my $service = shift;
  my $field   = shift;
  my $path    = shift;
  my $result  = "unknown";

  if ( $node->{client}->{$service}->{ $field . ".filename" } ) {
    $result = $node->{client}->{$service}->{ $field . ".filename" };
  } elsif ($path) {
    if ( !defined( $node->{client}->{$service}->{ $field . ".label" } ) ) {
      $self->log->debug("Setting label: $field\n");
      $node->{client}->{$service}->{ $field . ".label" } = $field;
    }

    if ( $path =~ /^\s*([^:;]+)[:;]([^:]+):([^:\.]+)[:\.]([^:\.]+)\s*$/ ) {
      $result = $self->get_filename( $config, $3, $4 );
      $self->log->debug("Expanding $path...\n");
      if ( !defined $node->{client}->{$service}->{ $field . "label" } ) {
        for my $f ( @{ $self->copy_fields } ) {
          if ( not exists $node->{client}->{$service}->{"$field.$f"}
            and
            exists $config->{'domain'}->{$1}->{'node'}->{$2}->{'client'}->{$3}
            ->{"$4.$f"} ) {
            $node->{client}->{$service}->{"$field.$f"} =
              $config->{'domain'}->{$1}->{'node'}->{$2}->{'client'}->{$3}
              ->{"$4.$f"};
          }
        }
      }
    } elsif ( $path =~ /^\s*([^:]+):([^:\.]+)[:\.]([^:\.]+)\s*$/ ) {
      $self->log->debug("Expanding $path...\n");
      $result = $self->get_filename( $2, $3 );
      for my $f ( @{ $self->copy_fields } ) {
        if ( not exists $node->{client}->{$service}->{"$field.$f"}
          and
          exists $config->{'domain'}->{$domain}->{'node'}->{$1}->{'client'}
          ->{$2}->{"$3.$f"} ) {
          $self->log->debug("Copying $f...\n");
          $node->{client}->{$service}->{"$field.$f"} =
            $config->{'domain'}->{$domain}->{'node'}->{$1}->{'client'}->{$2}
            ->{"$3.$f"};
        }
      }
    } elsif ( $path =~ /^\s*([^:\.]+)[:\.]([^:\.]+)\s*$/ ) {
      $self->log->debug("Expanding $path...\n");
      $result = $self->get_filename( $1, $2 );
      for my $f ( @{ $self->copy_fields } ) {
        if ( not exists $node->{client}->{$service}->{"$field.$f"}
          and exists $node->{client}->{$1}->{"$2.$f"} ) {
          $node->{client}->{$service}->{"$field.$f"} =
            $node->{client}->{$1}->{"$2.$f"};
        }
      }
    } elsif ( $path =~ /^\s*([^:\.]+)\s*$/ ) {
      $self->log->debug("Expanding $path...\n");
      $result = $self->get_filename( $service, $1 );
      for my $f ( @{ $self->copy_fields } ) {
        if ( not exists $node->{client}->{$service}->{"$field.$f"}
          and exists $node->{client}->{$service}->{"$1.$f"} ) {
          $node->{client}->{$service}->{"$field.$f"} =
            $node->{client}->{$service}->{"$1.$f"};
        }
      }
    }
  } else {
    $self->log->debug("\nDEBUG5: Doing path...\n");
    $result = $self->get_filename( $service, $field );
  }
  return $result;
}

sub single_value {
  my $self    = shift;
  my $node    = $self->get_node_config;
  my $service = shift;
  my $field   = shift;
  my $order   = shift;

  return 1 if @$order == 1;
  return 1
    if (@$order == 2
    and $node->{client}->{$service}->{ $field . ".negative" } );

  my $graphable = 0;
  if ( !defined $node->{client}->{$service}->{"graphable"} ) {

    #	foreach my $field (keys %{$node->{client}->{$service}})
    foreach my $field ( $self->get_field_order($service) ) {
      $self->log->debug("single_value: Checking field \"$field\".\n");
      if ( $field =~ /^([^\.]+)\.label/ or $field =~ /=/ ) {
        $graphable++ if $self->draw_field( $service, $1 );
      }
    }
    $node->{client}->{$service}->{"graphable"} = $graphable;
  }
  return 1 if ( $node->{client}->{$service}->{"graphable"} == 1 );

  return 0;
}

sub draw_field {
  my $self    = shift;
  my $node    = $self->get_node_config;
  my $service = shift;
  my $field   = shift;

  $field =~ s/=.*//;

  $self->log->debug( "munin_draw_field: Checking $service -> $field: "
      . $self->get_bool_val( $service, $field . ".graph", 1 )
      . ".\n" );
  return 0
    if ( exists $node->{client}->{$service}->{ $field . ".skipdraw" } );
  return ( $self->get_bool_val( $service, $field . ".graph", 1 ) );
}

sub expand_specials {
  my $self    = shift;
  my $service = shift;
  my $preproc = shift;
  my $order   = shift;
  my $node    = $self->get_node_config;
  my $config  = $self->config;
  my $domain  = $self->domain;
  my $single  = shift;
  my $result  = [];

  my $fieldnum = 0;
  for my $field (@$order) {    # Search for 'specials'...

    if ( $field =~ /^-(.+)$/ ) {
      $field = $1;
      unless ( defined $node->{client}->{$service}->{ $field . ".graph" }
        or defined $node->{client}->{$service}->{ $field . ".skipdraw" } ) {
        $node->{client}->{$service}->{ $field . ".graph" } = "no";
      }
    }

    $fieldnum++;
    my $tmp_field;
    if (
      defined( $tmp_field = $self->get_stack_command( $service, $field ) ) ) {
      $self->log->debug("Doing special_stack...\n");
      my @spc_stack = ();
      foreach my $pre ( split( /\s+/, $tmp_field ) ) {
        ( my $name = $pre ) =~ s/=.+//;
        if ( !@spc_stack ) {
          $node->{client}->{$service}->{ $name . ".draw" } =
            $node->{client}->{$service}->{ $field . ".draw" };
          $node->{client}->{$service}->{ $field . ".process" } = "no";
        } else {
          $node->{client}->{$service}->{ $name . ".draw" } = "STACK";
        }
        push( @spc_stack, $name );
        push( @$preproc,  $pre );
        push @$result, "$name.label";
        push @$result, "$name.draw";
        push @$result, "$name.cdef";

        $node->{client}->{$service}->{ $name . ".label" } = $name;
        $node->{client}->{$service}->{ $name . ".cdef" } =
          "$name,UN,0,$name,IF";
        if ( exists $node->{client}->{$service}->{ $field . ".cdef" }
          and !
          exists $node->{client}->{$service}->{ $name . ".onlynullcdef" } ) {
          $self->log->debug("NotOnlynullcdef ($field)...\n");
          $node->{client}->{$service}->{ $name . ".cdef" } .=
            "," . $node->{client}->{$service}->{ $field . ".cdef" };
          $node->{client}->{$service}->{ $name . ".cdef" } =~
            s/\b$field\b/$name/g;
        } else {
          $self->log->debug("Onlynullcdef ($field)...\n");
          $node->{client}->{$service}->{ $name . ".onlynullcdef" } = 1;
          push @$result, "$name.onlynullcdef";
        }
      }
    } elsif (
      defined( $tmp_field = $self->get_sum_command( $service, $field ) ) ) {
      my @spc_stack = ();
      my $last_name = "";
      $self->log->debug("Doing special_sum...\n");

      if ( @$order == 1
        or @$order == 2
        && $node->{client}->{$service}->{ $field . ".negative" } ) {
        $single = 1;
      }

      foreach my $pre ( split( /\s+/, $tmp_field ) ) {
        ( my $path = $pre ) =~ s/.+=//;
        my $name = "z" . $fieldnum . "_" . scalar(@spc_stack);
        $last_name = $name;

        $node->{client}->{$service}->{ $name . ".cdef" } =
          "$name,UN,0,$name,IF";
        $node->{client}->{$service}->{ $name . ".graph" } = "no";
        $node->{client}->{$service}->{ $name . ".label" } = $name;
        push @$result, "$name.cdef";
        push @$result, "$name.graph";
        push @$result, "$name.label";

        push( @spc_stack, $name );
        push( @$preproc,  "$name=$pre" );
      }
      $node->{client}->{$service}->{ $last_name . ".cdef" } .=
        "," . join( ',+,', @spc_stack[ 0 .. @spc_stack - 2 ] ) . ',+';
      if ( exists $node->{client}->{$service}->{ $field . ".cdef" }
        and length $node->{client}->{$service}->{ $field . ".cdef" } )
      {    # Oh bugger...
        my $tc = $node->{client}->{$service}->{ $field . ".cdef" };
        $self->log->debug("Oh bugger...($field)...\n");
        $tc =~
          s/\b$field\b/$node->{client}->{$service}->{$last_name.".cdef"}/;
        $node->{client}->{$service}->{ $last_name . ".cdef" } = $tc;
      }
      $node->{client}->{$service}->{ $field . ".process" } = "no";
      $node->{client}->{$service}->{ $last_name . ".draw" } =
        $node->{client}->{$service}->{ $field . ".draw" };
      $node->{client}->{$service}->{ $last_name . ".label" } =
        $node->{client}->{$service}->{ $field . ".label" };
      if ( defined $node->{client}->{$service}->{ $field . ".graph" } ) {
        $node->{client}->{$service}->{ $last_name . ".graph" } =
          $node->{client}->{$service}->{ $field . ".graph" };
      } else {
        $node->{client}->{$service}->{ $last_name . ".graph" } = "yes";
      }
      if ( defined $node->{client}->{$service}->{ $field . ".negative" } ) {
        $node->{client}->{$service}->{ $last_name . ".negative" } =
          $node->{client}->{$service}->{ $field . ".negative" };
      }
      $node->{client}->{$service}->{ $field . ".realname" } = $last_name;
      $self->log->debug(
"Setting node->{client}->{$service}->{$field} -> realname = $last_name...\n"
      );
    } elsif ( defined $node->{client}->{$service}->{ $field . ".negative" } )
    {
      my $nf = $node->{client}->{$service}->{ $field . ".negative" };
      unless ( defined $node->{client}->{$service}->{ $nf . ".graph" }
        or defined $node->{client}->{$service}->{ $nf . ".skipdraw" } ) {
        $node->{client}->{$service}->{ $nf . ".graph" } = "no";
      }
    }
  }
  return $result;
}

sub _sanitise_fieldname {
  my $self  = shift;
  my $lname = shift;
  my $done  = shift;
  my $old   = shift || 0;

  $lname =~ s/[\W-]/_/g;
  return substr( $lname, -18 ) if $old;

  #$lname = Digest::MD5::md5_hex ($lname) if (defined $done->{$lname});
  $done->{$lname} = 1;

  return $lname;
}

sub _read_socket {
  my $self   = shift;
  my $socket = shift;
  my @array;
  my $timed_out = 0;

  return undef unless defined $socket;

  eval {
    local $SIG{ALRM} = sub {
      $timed_out = 1;
      close $socket;
      $self->log_exception( "Timeout", "Timeout, aborting read: $!" );
    };
    alarm( $self->timeout );
    while (<$socket>) {
      chomp;
      last if (/^\.$/);
      push @array, $_;
    }
    alarm 0;
  };
  if ($timed_out) {
    $self->log->warning("Socket read timed out: $@\n");
    return undef;
  }
  $self->log->debug(
    "[DEBUG] Reading from socket: \"" . ( join( "|", @array ) ) . "\"." );
  return (@array);
}

sub _read_socket_single {
  my $self      = shift;
  my $socket    = shift;
  my $timed_out = 0;
  my $res;

  return undef unless defined $socket;

  eval {
    local $SIG{ALRM} = sub {
      $timed_out = 1;
      close $socket;
      $self->log_exception( "Timeout",
        "[WARNING] Timeout: Aborting read: $!" );
    };
    alarm( $self->timeout );
    $res = <$socket>;
    chomp $res if defined $res;
    alarm 0;
  };
  if ($timed_out) {
    $self->log->warning("Socket read timed out: $@\n");
    return undef;
  }
  $self->log->debug("[DEBUG] Reading from socket: \"$res\".");
  return $res;
}

sub _write_socket_single {
  my $self      = shift;
  my $socket    = shift;
  my $text      = shift;
  my $timed_out = 0;
  $self->log->debug("Writing to socket: \"$text\".");
  eval {
    local $SIG{ALRM} = sub { die "Could not run list on socket: $!\n" };
    alarm 5;
    print $socket $text;
    alarm 0;
  };
  return 1;
}

1;
