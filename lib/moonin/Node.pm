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
has 'limit_services' =>
  ( is => 'rw', required => 0, default => undef );

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
    $self->fetch( $socket );

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
    next if ( $self->limit_services and !grep ( /^$service$/, @{$self->limit_services} ) );
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
    $self->config->store->dbm->{FS}->{$domain}->{$name}->{$service} = $servicefetch_time;
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
    $self->config->store->dbm->{'CS'}->{$domain}->{$name}->{$servname} = $serviceconf_time;
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
