#
# Moonin::Config
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

package Moonin::Config;

use Moose;
use Moonin::Config::Store;
use Data::Dump qw(dump);

with 'MooseX::Role::Log4perl', 'Moonin::Role::Exception';

has 'config'      => ( is => 'rw', isa => 'HashRef', required => 0 );
has 'config_file' => ( is => 'rw', isa => 'Str',     required => 1 );
has 'missingok' => ( is => 'rw', isa => 'Bool', required => 0, default => 0 );
has 'corruptok' => ( is => 'rw', isa => 'Bool', required => 0, default => 0 );
has 'store' => ( is => 'ro', isa => 'Object', required => 0 );
has 'legal' => (
  is      => 'ro',
  isa     => 'ArrayRef',
  default => sub {
    [
      "tmpldir",                "ncsa",
      "ncsa_server",            "ncsa_config",
      "rundir",                 "dbdir",
      "logdir",                 "htmldir",
      "include",                "domain_order",
      "node_order",             "graph_order",
      "graph_sources",          "fork",
      "graph_title",            "create_args",
      "graph_args",             "graph_vlabel",
      "graph_vtitle",           "graph_total",
      "graph_scale",            "graph",
      "update",                 "host_name",
      "label",                  "cdef",
      "draw",                   "graph",
      "max",                    "min",
      "negative",               "skipdraw",
      "type",                   "warning",
      "critical",               "special_stack",
      "special_sum",            "stack",
      "sum",                    "address",
      "htaccess",               "warn",
      "use_default_name",       "use_node_name",
      "port",                   "graph_noscale",
      "nsca",                   "nsca_server",
      "nsca_config",            "extinfo",
      "fetch_data",             "filename",
      "max_processes",          "nagios",
      "info",                   "graph_info",
      "graph_category",         "graph_strategy",
      "graph_width",            "graph_height",
      "graph_sums",             "local_address",
      "compare",                "text",
      "command",                "contact",
      "contacts",               "max_messages",
      "always_send",            "notify_alias",
      "line",                   "state",
      "graph_period",           "cgiurl_graph",
      "cgiurl",                 "tls",
      "service_order",          "category_order",
      "version",                "tls_certificate",
      "tls_private_key",        "tls_pem",
      "tls_verify_certificate", "tls_verify_depth",
      "graph_data_size",        "colour",
      "graph_printf",           "ok",
      "unknown",                "extrasdir"
    ];
  },
);
has 'legal_expanded' => ( is => 'ro', isa => 'HashRef' );

sub BUILD {
  my $self = shift;

  my $config   = undef;
  my @contents = undef;

  my %legal_expanded = map { $_ => 1 } @{ $self->legal };
  $self->{legal_expanded} = \%legal_expanded;

  my $conf = $self->config_file;
  if ( !-r $conf and !$self->missingok ) {
    $self->log_exception( 'Config', "cannot open config file '$conf'" );
  }
  if ( open( CFG, $conf ) ) {
    @contents = <CFG>;
    close(CFG);
  }

  $self->_parse_config( \@contents );

  # Some important defaults before we return...
  $self->config->{'rundir'}  ||= "/tmp/";
  $self->config->{'dbdir'}   ||= "/var/lib/munin/";
  $self->config->{'logdir'}  ||= "/var/log/";
  $self->config->{'tmpldir'} ||= "/etc/munin/templates/";
  $self->config->{'htmldir'} ||= "/usr/share/munin/html";

  # Set up all the methods for our config object.
  foreach my $attr ( @{ $self->legal } ) {
    $self->meta->add_method(
      $attr => sub {
        my $obj = shift;
        return $obj->config->{$attr} || undef;
      }
    );
  }

  $self->{store} = Moonin::Config::Store->new( directory => $self->dbdir );

  # $self->log->debug(dump($self->config));
}

sub get_domains {
  my $self   = shift;
  my @result = sort( keys( %{ $self->domain } ) );
  return \@result;
}

sub get_nodes {
  my $self   = shift;
  my $domain = shift;
  my @result = sort( keys( %{ $self->domain->{$domain}->{node} } ) );
  return \@result;
}

sub get_all_graph_categories {
  my $self = shift;

  my @results;
  my @keys = $self->store->keys;
  foreach my $key (@keys) {
    next if $key !~ /^node-(.+?)-(.+)$/;
    my $clients = $self->store->get($key)->{client};
    foreach my $thing ( keys( %{$clients} ) ) {
      if ( exists $clients->{$thing}->{'graph_category'} ) {
        my $gc = ucfirst( $clients->{$thing}->{'graph_category'} );
        push( @results, $gc )
          unless ( grep /^$gc$/, @results );
      }
    }
  }
  @results = sort(@results);
  return \@results;
}

sub get_all_graphs_by_category {
  my $self     = shift;
  my $category = shift;
  my $graph    = shift;

  my $graphs = {};
  my @keys   = $self->store->keys;
  foreach my $node (@keys) {
    next if $node !~ /^node-(.+?)-(.+)$/;
    my $clients = $self->store->get($node)->{client};
    foreach my $thing ( keys( %{$clients} ) ) {
      if ( exists $clients->{$thing}->{'graph_category'} ) {
        my $gc = ucfirst( $clients->{$thing}->{'graph_category'} );
        if ( defined $category ) {
          if ( $gc eq $category ) {
            if ( defined $graph ) {
              push(
                @{ $graphs->{$gc} },
                { name => $thing, data => $clients->{$thing} }
              ) if $graph eq $thing;

            } else {
              push(
                @{ $graphs->{$gc} },
                { name => $thing, data => $clients->{$thing} }
              );
            }
          }
        } else {
          push(
            @{ $graphs->{$gc} },
            { name => $thing, data => $clients->{$thing} }
          );
        }
      }
    }
    foreach my $key ( keys( %{$graphs} ) ) {
      my @sorted =
        sort { $a->{data}->{graph_title} cmp $b->{data}->{graph_title} }
        @{ $graphs->{$key} };
      $graphs->{$key} = \@sorted;
    }
  }
  return $graphs;
}

sub get_all_nodes_by_graph {
  my $self  = shift;
  my $graph = shift;

  my $nodes = {};
  my @keys  = $self->store->keys;
  foreach my $node (@keys) {
    next if $node !~ /^node-(.+?)-(.+)$/;
    my $domainname = $1;
    my $nodename   = $2;
    my $clients    = $self->store->get($node)->{client};
    foreach my $client ( keys( %{$clients} ) ) {
      push(
        @{ $nodes->{$client} },
        {
          domain => $domainname,
          node   => $nodename,
          graph  => $clients->{$client}
        }
      );
    }
  }
  foreach my $key ( keys( %{$nodes} ) ) {
    my @sorted = sort {
      $a->{client}->{$key}->{data}->{graph_title}
        cmp $b->{client}->{$key}->{data}->{graph_title}
    } @{ $nodes->{$key} };
    $nodes->{$key} = \@sorted;
  }
  return $nodes;
}

sub get_graph_categories {
  my $self   = shift;
  my $domain = shift;
  my $name   = shift;

  if ($self->store->exists("node-$domain-$name")) {
    my $clients = $self->store->get("node-$domain-$name")->{client};

    my @graph_categories;
    foreach my $thing ( keys( %{$clients} ) ) {
      if ( exists $clients->{$thing}->{'graph_category'} ) {
        my $gc = ucfirst( $clients->{$thing}->{'graph_category'} );
        push( @graph_categories, $gc )
          unless ( grep /^$gc$/, @graph_categories );
      }
    }
    @graph_categories = sort(@graph_categories);
    return \@graph_categories;
  } else {
    if ( exists $self->config->{'domain'}->{$domain} ) {
      if ( exists $self->config->{'domain'}->{$domain}->{'node'}->{$name} ) {
        my $clients = $self->config->{'domain'}->{$domain}->{'node'}->{$name};
        my @graph_categories;
        foreach my $thing ( keys ( %{$clients} ) ) ) {
          if ( exists $clients->{$thing}->{'graph_category'} ) {
            my $gc = ucfirst( $clients->{$thing}->{'graph_category'} );
            push( @graph_categories, $gc )
              unless ( grep /^$gc$/, @graph_categories );
          }
        }
        @graph_categories = sort(@graph_categories);
        return \@graph_categories; 
      }
    }
    return [];
  }
}

sub get_graphs_by_category {
  my $self     = shift;
  my $domain   = shift;
  my $name     = shift;
  my $category = shift;
  my $graph    = shift;

  my $clients = $self->store->get("node-$domain-$name")->{client};
  my $graphs  = {};
  foreach my $thing ( keys( %{$clients} ) ) {
    if ( exists $clients->{$thing}->{'graph_category'} ) {
      my $gc = ucfirst( $clients->{$thing}->{'graph_category'} );
      if ( defined $category ) {
        if ( $gc eq $category ) {
          if ( defined $graph ) {
            push(
              @{ $graphs->{$gc} },
              { name => $thing, data => $clients->{$thing} }
            ) if $graph eq $thing;

          } else {
            push(
              @{ $graphs->{$gc} },
              { name => $thing, data => $clients->{$thing} }
            );
          }
        }
      } else {
        push(
          @{ $graphs->{$gc} },
          { name => $thing, data => $clients->{$thing} }
        );
      }
    }
  }
  foreach my $key ( keys( %{$graphs} ) ) {
    my @sorted =
      sort { $a->{data}->{graph_title} cmp $b->{data}->{graph_title} }
      @{ $graphs->{$key} };
    $graphs->{$key} = \@sorted;
  }
  return $graphs;
}

sub _parse_config {
  my $self     = shift;
  my $lines    = shift;
  my $hash     = $self->config;
  my $prefix   = "";
  my $prevline = "";

  foreach my $line ( @{$lines} ) {
    chomp $line;

    #$line =~ s/(^|[^\\])#.*/$1/g if $line =~ /#/;  # Skip comments...
    if ( $line =~ /#/ ) {
      next if ( $line =~ /^#/ );
      $line =~ s/(^|[^\\])#.*/$1/g;
      $line =~ s/\\#/#/g;
    }
    next unless ( $line =~ /\S/ );    # And empty lines...
    if ( length $prevline ) {
      $line     = $prevline . $line;
      $prevline = "";
    }
    if ( $line =~ /\\\\$/ ) {
      $line =~ s/\\\\$/\\/;
    } elsif ( $line =~ /\\$/ ) {
      ( $prevline = $line ) =~ s/\\$//;
      next;
    }
    $line =~ s/\s+$//g;               # And trailing whitespace...
    $line =~ s/^\s+//g;               # And heading whitespace...

    if ( $line =~ /^\.(\S+)\s+(.+)\s*$/ ) {
      my ( $var, $val ) = ( $1, $2 );
      $self->_set_var_path( $var, $val );
    } elsif ( $line =~ /^\s*\[([^\]]*)]\s*$/ ) {
      $prefix = $1;
      if ( $prefix =~ /^([^:;]+);([^:;]+)$/ ) {
        $prefix .= ":";
      } elsif ( $prefix =~ /^([^:;]+);$/ ) {
        $prefix .= "";
      } elsif ( $prefix =~ /^([^:;]+);([^:;]+):(.*)$/ ) {
        $prefix .= ".";
      } elsif ( $prefix =~ /^([^:;]+)$/ ) {
        ( my $domain = $prefix ) =~ s/^[^\.]+\.//;
        $prefix = "$domain;$prefix:";
      } elsif ( $prefix =~ /^([^:;]+):(.*)$/ ) {
        ( my $domain = $prefix ) =~ s/^[^\.]+\.//;
        $prefix = "$domain;$prefix.";
      }
    } elsif ( $line =~ /^\s*(\S+)\s+(.+)\s*$/ ) {
      my ( $var, $val ) = ( $1, $2 );
      $self->_set_var_path( "$prefix$var", $val );
    } else {
      warn "Malformed configuration line \"$line\".";
    }
  }

  return 1;
}

sub _set_var_path {
  my $self = shift;
  my $hash = $self->config;
  my $var  = shift;
  my $val  = shift;

  $self->log->debug("Setting var \"$var\" = \"$val\"\n");
  if ( $var =~ /^\s*([^;:]+);([^:]+):(\S+)\s*$/ ) {
    my ( $dom, $host, $rest ) = ( $1, $2, $3 );
    my @sp = split( /\./, $rest );

    if ( @sp == 3 ) {
      $self->log->warn(
        "Unknown option \"$sp[2]\" in \"$dom;$host:$sp[0].$sp[1].$sp[2]\".")
        unless defined $self->legal_expanded->{ $sp[2] };
      $hash->{domain}->{$dom}->{node}->{$host}->{client}->{ $sp[0] }
        ->{"$sp[1].$sp[2]"} = $val;
    } elsif ( @sp == 2 ) {
      $self->log->warn(
        "Unknown option \"$sp[1]\" in \"$dom;$host:$sp[0].$sp[1]\".")
        unless defined $self->legal_expanded->{ $sp[1] };
      $hash->{domain}->{$dom}->{node}->{$host}->{client}->{ $sp[0] }
        ->{ $sp[1] } = $val;
    } elsif ( @sp == 1 ) {
      $self->log->warn("Unknown option \"$sp[0]\" in \"$dom;$host:$sp[0]\".")
        unless defined $self->legal_expanded->{ $sp[0] };
      $hash->{domain}->{$dom}->{node}->{$host}->{ $sp[0] } = $val;
    } else {
      warn "_set_var: Malformatted variable path \"$var\".";
    }
  } elsif ( $var =~ /^\s*([^;:]+);([^;:]+)\s*$/ ) {
    my ( $dom, $rest ) = ( $1, $2 );
    my @sp = split( /\./, $rest );

    if ( @sp == 1 ) {
      $self->log->warn("Unknown option \"$sp[0]\" in \"$dom;$sp[0]\".")
        unless defined $self->legal_expanded->{ $sp[0] };
      $hash->{domain}->{$dom}->{ $sp[0] } = $val;
    } else {
      warn "_set_var: Malformatted variable path \"$var\".";
    }
  } elsif ( $var =~ /^\s*([^;:\.]+)\s*$/ ) {
    $self->log->warn("Unknown option \"$1\" in \"$1\".")
      unless defined $self->legal_expanded->{$1};
    $hash->{$1} = $val;
  } elsif ( $var =~ /^\s*([^\.]+)\.([^\.]+)\.([^\.]+)$/ ) {
    $self->log->warn("Unknown option \"$1\" in \"$var\".")
      unless defined $self->legal_expanded->{$1};
    $self->log->warn("Unknown option \"$3\" in \"$var\".")
      unless defined $self->legal_expanded->{$3};
    $hash->{$1}->{$2}->{$3} = $val;
  } else {
    warn "_set_var: Malformatted variable path \"$var\".";
  }
  $self->config($hash);

  return 1;
}

sub domain {
  my ($self) = @_;
  return $self->config->{domain};
}

sub get {
  my $self    = shift;
  my $field   = shift;
  my $default = shift;
  my $domain  = shift;
  my $node    = shift;
  my $service = shift;
  my $plot    = shift;
  my $conf    = $self->config;
  my $nconf = $self->store->get("node-" . $domain . "-" . $node);
  
  if ( defined $field ) {
    return $nconf->{client}->{$service}
      ->{"$plot.$field"}
      if (defined $domain
      and defined $node
      and defined $service
      and defined $plot
      and defined $nconf->{client}->{$service}->{"$plot.$field"} );

    return $nconf->{client}->{$service}->{$field}
      if (defined $domain
      and defined $node
      and defined $service
      and defined $nconf->{client}->{$service}->{$field} );
    return $conf->{domain}->{$domain}->{node}->{$node}->{$field}
      if (defined $domain
      and defined $node
      and defined $conf->{domain}->{$domain}->{node}->{$node}->{$field} );
    return $conf->{domain}->{$domain}->{$field}
      if ( defined $domain and defined $conf->{domain}->{$domain}->{$field} );
    return $conf->{$field}
      if ( defined $conf->{$field} );
    return $default;
  } else {
    return $nconf->{client}->{$service}
      if (defined $domain
      and defined $node
      and defined $service
      and defined $nconf->{client}->{$service} );
    return $conf->{domain}->{$domain}->{node}->{$node}
      if (defined $domain
      and defined $node
      and defined $conf->{domain}->{$domain}->{node}->{$node} );
    return $conf->{domain}->{$domain}
      if ( defined $domain and defined $conf->{domain}->{$domain} );
    return $conf
      if ( defined $conf );
    return $default;
  }
}

1;
