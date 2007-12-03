#
# Moonin::Graph
#
# Portions taken from Munin
# Copyright (C) 2002-2006 Jimmy Olsen, Audun Ytterdal, Nicolai Langfeldt
#
# Created On: Thu May 17 16:04:12 PDT 2007
# Created By: Adam Jacob, <adam@hjksolutions.com>
#
# Copyright 2007, HJK Solutions
#
# $Id$
#

package Moonin::Graph;

use Moose;
use RRDs;
use POSIX qw(strftime);
use Digest::MD5;
use Time::HiRes;

with 'MooseX::Role::Log4perl', 'Moonin::Role::Exception';

has 'node' => ( is => 'rw', isa => 'Object', required => 1 );
has 'colour' => (
  is       => 'rw',
  isa      => 'ArrayRef',
  required => 0,
  default  => sub {
    [
      "#22ff22", "#0022ff", "#ff0000", "#00aaaa", "#ff00ff", "#ffa500",
      "#cc0000", "#0000cc", "#0080C0", "#8080C0", "#FF0080", "#800080",
      "#688e23", "#408080", "#808000", "#000000", "#00FF00", "#0080FF",
      "#FF8000", "#800000", "#FB31FB"
    ];
  }
);
has 'range_colour'  => ( is => 'rw', isa => 'Str', default => '#22ff22' );
has 'single_colour' => ( is => 'rw', isa => 'Str', default => '#00aa00' );
has 'times'         => (
  is      => 'ro',
  isa     => 'HashRef',
  default => sub {
    {
      "day"   => "-30h",
      "week"  => "-8d",
      "month" => "-33d",
      "year"  => "-400d"
    };
  }
);
has 'resolutions' => (
  is      => 'ro',
  isa     => 'HashRef',
  default => sub {
    {
      "day"   => "300",
      "week"  => "1500",
      "month" => "7200",
      "year"  => "86400"
    };
  }
);
has 'sumtimes' => (
  is      => 'ro',
  isa     => 'HashRef',
  default => sub {
    {
      "week" => [ "hour", 12 ],
      "year" => [ "day",  288 ]
    };
  }
);

has 'force_graphing' => ( is => 'rw', isa => 'Num', default => 0 );
has 'force_lazy'     => ( is => 'rw', isa => 'Num', default => 1 );

# RRDtool 1.2 requires \\: in comments
has 'rrdkludge' => (
  is  => 'ro',
  isa => 'Str',
);

has 'linekludge' => (
  is  => 'ro',
  isa => 'Str',
);

has 'draw' => (
  is      => 'rw',
  isa     => 'HashRef',
  default => sub {
    return {
      "day"     => 1,
      "week"    => 1,
      "month"   => 1,
      "year"    => 1,
      "sumyear" => 1,
      "sumweek" => 1
    };
  }
);

has 'to_file' => ( is => 'rw', isa => 'Str', default => 0, required => 1 );

sub BUILD {
  my $self = shift;
  $self->{rrdkludge} = $RRDs::VERSION < 1.2 ? '' : '\\';
  $self->{linekludge} = $RRDs::VERSION >= 1.2 ? 1 : 0;
}

sub _get_field_name {
  my $self = shift;
  my $name = shift;

  $name = substr( Digest::MD5::md5_hex($name), -15 )
    if ( length $name > 15 );

  return $name;
}

sub _set_cdef_name {
  my $self    = shift;
  my $service = shift;
  my $field   = shift;
  my $new     = shift;

  $service->{ $field . ".cdef_name" } = $new;
  $self->log->debug("set_cdef_name from $field to $new.\n");
}

sub _graph_by_minute {
  my $self    = shift;
  my $domain  = shift;
  my $name    = shift;
  my $service = shift;

  return (
    $self->node->config->get( "graph_period", "second", $domain, $name,
      $service ) eq "minute"
  );
}

sub _orig_to_cdef {
  my $self    = shift;
  my $service = shift;
  my $field   = shift;

  if ( defined $service->{ $field . ".cdef_name" } ) {
    return $self->_orig_to_cdef( $service,
      $service->{ $field . ".cdef_name" } );
  }
  return $field;
}

sub _expand_cdef {
  my $self       = shift;
  my $service    = shift;
  my $cfield_ref = shift;
  my $cdef       = shift;

  my $new_field = $self->_get_field_name("cdef$$cfield_ref");

  my ( $max, $min, $avg ) = (
    "CDEF:a$new_field=$cdef", "CDEF:i$new_field=$cdef",
    "CDEF:g$new_field=$cdef"
  );

  foreach my $field ( keys %$service ) {
    next unless ( $field =~ /^(.+)\.label$/ );
    my $fieldname = $1;
    my $rrdname = $self->_orig_to_cdef( $service, $fieldname );
    if ( $cdef =~ /\b$fieldname\b/ ) {
      $max =~ s/([,=])$fieldname([,=]|$)/$1a$rrdname$2/g;
      $min =~ s/([,=])$fieldname([,=]|$)/$1i$rrdname$2/g;
      $avg =~ s/([,=])$fieldname([,=]|$)/$1g$rrdname$2/g;
    }
  }

  $self->_set_cdef_name( $service, $$cfield_ref, $new_field );
  $$cfield_ref = $new_field;

  return ( $max, $min, $avg );
}

sub _escape {
  my $self = shift;
  my $text = shift;
  return undef if not defined $text;
  $text =~ s/\\/\\\\/g;
  $text =~ s/:/\\:/g;
  return $text;
}

sub get_picture_filename {
  my $self    = shift;
  my $config  = $self->node->config;
  my $domain  = $self->node->domain;
  my $name    = $self->node->name;
  my $service = shift;
  my $scale   = shift;
  my $sum     = shift;
  my $dir     = $config->htmldir;

  # Sanitise
  $dir     =~ s/[^\w_\/"'\[\]\(\)+=-]\./_/g;
  $domain  =~ s/[^\w_\/"'\[\]\(\)+=\.-]/_/g;
  $name    =~ s/[^\w_\/"'\[\]\(\)+=\.-]/_/g;
  $service =~ s/[^\w_\/"'\[\]\(\)+=-]/_/g;
  $scale   =~ s/[^\w_\/"'\[\]\(\)+=-]/_/g;

  if ( defined $sum and $sum ) {
    return "$dir/$domain/$name-$service-$scale-sum.png";
  } else {
    return "$dir/$domain/$name-$service-$scale.png";
  }
}

sub _get_title {
  my $self    = shift;
  my $node    = $self->node->get_node_config;
  my $service = shift;
  my $scale   = shift;

  return (
      $node->{client}->{$service}->{'graph_title'}
    ? $node->{client}->{$service}->{'graph_title'}
    : $service
  ) . " - by $scale";
}

sub _get_custom_graph_args {
  my $self    = shift;
  my $node    = $self->node->get_node_config;
  my $service = shift;
  my $result  = [];

  if ( $node->{client}->{$service}->{graph_args} ) {
    push @$result, split /\s/, $node->{client}->{$service}->{graph_args};
    return $result;
  } else {
    return undef;
  }
}

sub _get_vlabel {
  my $self    = shift;
  my $node    = $self->node->get_node_config;
  my $service = shift;
  my $scale   = shift;

  if ( $node->{client}->{$service}->{graph_vlabel} ) {
    ( my $res = $node->{client}->{$service}->{graph_vlabel} ) =~
      s/\$\{graph_period\}/$scale/g;
    return $res;
  } elsif ( $node->{client}->{$service}->{graph_vtitle} ) {
    return $node->{client}->{$service}->{graph_vtitle};
  }
  return undef;
}

sub _should_scale {
  my $self    = shift;
  my $node    = $self->node->get_node_config;
  my $service = shift;

  if ( defined $node->{client}->{$service}->{graph_scale} ) {
    return $self->node->get_bool_val( $service, 'graph_scale', 1 );
  } elsif ( defined $node->{client}->{$service}->{graph_noscale} ) {
    return !$self->node->get_bool_val( $service, 'graph_noscale', 0 );
  }

  return 1;
}

sub _get_header {
  my $self    = shift;
  my $node    = $self->node;
  my $config  = $self->node->config;
  my $domain  = $self->node->domain;
  my $host    = $self->node->name;
  my $service = shift;
  my $scale   = shift;
  my $sum     = shift;
  my $result  = [];
  my $tmp_field;

  # Picture filename
  push @$result,
    $self->get_picture_filename( $service, $scale, $sum || undef );

  # Title
  push @$result, ( "--title", $self->_get_title( $service, $scale ) );

  # When to start the graph
  push @$result, "--start", $self->times->{$scale};

  # Custom graph args, vlabel and graph title
  if ( defined( $tmp_field = $self->_get_custom_graph_args($service) ) ) {
    push( @$result, @{$tmp_field} );
  }
  if (
    defined(
      $tmp_field = $self->_get_vlabel(
        $node, $service,
        $self->node->config->get(
          "graph_period", "second", $domain, $host, $service
        )
      )
    )
    ) {
    push @$result, ( "--vertical-label", $tmp_field );
  }

  push @$result, "--height",
    $self->node->config->get( "graph_height", "175", $domain, $host,
    $service );
  push @$result, "--width",
    $self->node->config->get( "graph_width", "400", $domain, $host,
    $service );
  push @$result, "--imgformat", "PNG";
  push @$result, "--lazy" if ( $self->force_lazy );

  push( @$result, "--units-exponent", "0" )
    if ( !$self->_should_scale($service) );

  return $result;
}

sub process_all {
  my ($self) = @_;
  foreach my $service ( keys( %{ $self->node->get_node_config->{client} } ) )
  {
    $self->logger->debug("Doing $service");
    $self->process($service);
  }
}

sub process {
  my ( $self, $service, $draw_time ) = @_;
  my $domain = $self->node->domain;
  my $name   = $self->node->name;
  my $node   = $self->node->get_node_config;

  $self->log_exception( 'InvalidArgument', "Must supply a service!" )
    unless $service;

  my %times = %{ $self->times };

  if ($draw_time) {
    $self->log_exception( 'InvalidArgument', "You must supply a valid time!" )
      unless exists $self->times->{$draw_time};
    %times = ( $draw_time => $self->times->{$draw_time}, );
  }

  # Make my graphs
  $self->log->debug("Generating Graphs for $name service $service");
  $self->log_exception( 'InvalidArgument',
    "Service $service must exist for $node!" )
    unless exists( $node->{client}->{$service} );

  my $service_time = Time::HiRes::time;
  my $lastupdate   = 0;
  my $now          = time;
  my $fnum         = 0;
  my @rrd;
  my @added = ();

  my $field_count   = 0;
  my $max_field_len = 0;
  my @field_order   = ();
  my $rrdname;
  my $force_single_value;

  # munin_set_context($node,$config,$domain,$name,$service);

  @field_order = @{ $self->node->get_field_order($service) };

  # Array to keep 'preprocess'ed fields.
  my @rrd_preprocess = ();
  $self->log->debug( "Expanding specials \"",
    join( "\",\"", @field_order ), "\".\n" );

  @added =
    @{ $self->node->expand_specials( $service, \@rrd_preprocess,
      \@field_order ) };

  @field_order = ( @rrd_preprocess, @field_order );
  $self->log->debug( "Checking field lengths \"",
    join( "\",\"", @rrd_preprocess ), "\".\n" );

  # Get max label length
  $max_field_len =
    $self->node->get_max_label_length( $service, \@field_order );

  # my $global_headers = ($max_field_len >= 16);
  # Global headers makes the value tables easier to read no matter how
  # wide the labels are.
  my $global_headers = 1;

  # Default format for printing under graph.
  my $avgformat;
  my $rrdformat = $avgformat = "%6.2lf";

  if ( exists $node->{client}->{$service}->{graph_args}
    and $node->{client}->{$service}->{graph_args} =~ /--base\s+1024/ ) {

    # If the base unit is 1024 then 1012.56 is a valid
    # number to show.  That's 7 positions, not 6.
    $rrdformat = $avgformat = "%7.2lf";
  }

  if ( exists $node->{client}->{$service}->{graph_printf} ) {

    # Plugin specified complete printf format
    $rrdformat = $node->{client}->{$service}->{graph_printf};
  }

  my $rrdscale = '';
  $rrdscale = '%s'
    if $self->node->get_bool_val( $service, 'graph_scale', 1 );

  # Array to keep negative data until we're finished with positive.
  my @rrd_negatives = ();
  my $filename      = "unknown";
  my %total_pos;
  my %total_neg;
  my $autostacking = 0;
  $self->log->debug( "Treating fields \"",
    join "\",\"", @field_order, "\".\n" );
  for my $field (@field_order) {
    my $path = undef;
    if ( $field =~ s/=(.+)// ) {
      $path = $1;
    }

    next unless $self->node->process_field( $service, $field );
    $self->log->debug("Processing field \"$field\".\n");

    my $fielddraw =
      $self->node->config->get( "draw", "LINE2", $domain, $name, $service,
      $field );

    if ( $field_count == 0 and $fielddraw eq 'STACK' ) {

      # Illegal -- first field is a STACK
      $self->log->error( "First field (\"$field\") of graph \"$domain\""
          . ":: \"$name\" :: \"$service\" is STACK. STACK can "
          . "only be drawn after a LINEx or AREA." );
      $fielddraw = "LINE2";
    }

    if ( $fielddraw eq 'AREASTACK' ) {
      if ( $autostacking == 0 ) {
        $fielddraw    = 'AREA';
        $autostacking = 1;
      } else {
        $fielddraw = 'STACK';
      }
    }

    if ( $fielddraw =~ /LINESTACK(\d+(?:.\d+)?)/ ) {
      if ( $autostacking == 0 ) {
        $fielddraw    = "LINE$1";
        $autostacking = 1;
      } else {
        $fielddraw = 'STACK';
      }
    }

    # Getting name of rrd file
    $filename = $self->node->get_rrd_filename( $service, $field, $path );

    my $update = RRDs::last($filename);
    $update = 0 if !defined $update;
    if ( $update > $lastupdate ) {
      $lastupdate = $update;
    }

    # It does not look like $fieldname.rrdfield is possible to set
    my $rrdfield =
      ( $node->{client}->{$service}->{ $field . ".rrdfield" } || "42" );

    my $single_value = $force_single_value
      || $self->node->single_value( $service, $field, \@field_order );

    my $has_negative =
      exists $node->{client}->{$service}->{ $field . ".negative" }
      && $node->{client}->{$service}->{ $field . ".negative" };

    # Trim the fieldname to make room for other field names.
    $rrdname = $self->_get_field_name($field);
    if ( $rrdname ne $field ) {

      # A change was made
      $self->_set_cdef_name( $node->{client}->{$service}, $field, $rrdname );
    }

    push( @rrd, "DEF:g$rrdname=" . $filename . ":" . $rrdfield . ":AVERAGE" );
    push( @rrd, "DEF:i$rrdname=" . $filename . ":" . $rrdfield . ":MIN" );
    push( @rrd, "DEF:a$rrdname=" . $filename . ":" . $rrdfield . ":MAX" );

    if ( exists $node->{client}->{$service}->{ $field . ".onlynullcdef" }
      and $node->{client}->{$service}->{ $field . ".onlynullcdef" } ) {
      push( @rrd,
        "CDEF:c$rrdname=g$rrdname"
          . ( ( $now - $update ) > 900 ? ",POP,UNKN" : "" ) );
    }

    if ( ( $node->{client}->{$service}->{ $field . ".type" } || "GAUGE" ) ne
      "GAUGE"
      and $self->_graph_by_minute( $domain, $name, $service ) ) {
      push(
        @rrd,
        $self->_expand_cdef(
          $node->{client}->{$service},
          \$rrdname, "$field,60,*"
        )
      );
    }

    if ( $node->{client}->{$service}->{ $field . ".cdef" } ) {
      push(
        @rrd,
        $self->_expand_cdef(
          $node->{client}->{$service}, \$rrdname,
          $node->{client}->{$service}->{ $field . ".cdef" }
        )
      );
      push( @rrd, "CDEF:c$rrdname=g$rrdname" );
      $self->log->debug("Field name after cdef set to $rrdname\n");
    } elsif (
      !(
        exists $node->{client}->{$service}->{ $field . ".onlynullcdef" }
        and $node->{client}->{$service}->{ $field . ".onlynullcdef" }
      )
      ) {
      push( @rrd,
        "CDEF:c$rrdname=g$rrdname"
          . ( ( $now - $update ) > 900 ? ",POP,UNKN" : "" ) );
    }

    next unless $self->node->draw_field( $service, $field );
    $self->log->debug("Drawing field \"$field\".\n");

    if ($single_value) {

      # Only one field. Do min/max range.
      push( @rrd, "CDEF:min_max_diff=a$rrdname,i$rrdname,-" );
      push( @rrd, "CDEF:re_zero=min_max_diff,min_max_diff,-" )
        unless ( $node->{client}->{$service}->{ $field . ".negative" } );
      push( @rrd, "AREA:i$rrdname#ffffff" );
      push( @rrd, "STACK:min_max_diff" . $self->range_colour );
      push( @rrd, "LINE2:re_zero#000000" )
        unless ( $node->{client}->{$service}->{ $field . ".negative" } );
    }

    if ( $has_negative and !@rrd_negatives ) {    # Push "global" headers...
      push( @rrd, "COMMENT:" . ( " " x $max_field_len ) );
      push( @rrd, "COMMENT:Cur (-/+)" );
      push( @rrd, "COMMENT:Min (-/+)" );
      push( @rrd, "COMMENT:Avg (-/+)" );
      push( @rrd, "COMMENT:Max (-/+) \\j" );
    } elsif ( $global_headers == 1 ) {
      push( @rrd, "COMMENT:" . ( " " x $max_field_len ) );
      push( @rrd, "COMMENT: Cur" . $self->rrdkludge . ":" );
      push( @rrd, "COMMENT:Min" . $self->rrdkludge . ":" );
      push( @rrd, "COMMENT:Avg" . $self->rrdkludge . ":" );
      push( @rrd, "COMMENT:Max" . $self->rrdkludge . ":  \\j" );
      $global_headers++;
    }

    my $colour;

    if ( exists $node->{client}->{$service}->{ $field . ".colour" } ) {
      $colour = "#" . $node->{client}->{$service}->{ $field . ".colour" };
    } elsif ($single_value) {
      $colour = $self->single_colour;
    } else {
      $colour = @{ $self->colour }[ $field_count % @{ $self->colour } ];
    }

    $field_count++;

    push(
      @rrd,
      $fielddraw . ":g$rrdname" . $colour . ":"
        . (
             $self->_escape( $node->{client}->{$service}->{"$field.label"} )
          || $self->_escape($field)
        )
        . (
        " " x (
          $max_field_len + 1 -
            length( $node->{client}->{$service}->{"$field.label"} || $field )
        )
        )
    );

    # Check for negative fields (typically network (or disk) traffic)
    if ($has_negative) {
      my $negfield = $self->_orig_to_cdef( $node->{client}->{$service},
        $node->{client}->{$service}->{ $field . ".negative" } );
      $self->log->debug("DEBUG: negfield = $negfield\n");
      if ( exists $node->{client}->{$service}->{ $negfield . ".realname" } ) {
        $negfield = $node->{client}->{$service}->{ $negfield . ".realname" };
      }

      if ( !@rrd_negatives ) {

        # zero-line, to redraw zero afterwards.
        push( @rrd_negatives, "CDEF:re_zero=g$negfield,UN,0,0,IF" );
      }

      push( @rrd_negatives, "CDEF:ng$negfield=g$negfield,-1,*" );

      if ($single_value) {

        # Only one field. Do min/max range.
        push( @rrd, "CDEF:neg_min_max_diff=i$negfield,a$negfield,-" );
        push( @rrd, "CDEF:ni$negfield=i$negfield,-1,*" );
        push( @rrd, "AREA:ni$negfield#ffffff" );
        push( @rrd, "STACK:neg_min_max_diff" . $self->range_colour );
      }

      push( @rrd_negatives, $fielddraw . ":ng$negfield" . $colour );

      # Draw HRULEs
      my $linedef =
        $self->node->config->get( "line", undef, $domain, $name, $service,
        $node->{client}->{$service}->{ $field . ".negative" } );
      if ($linedef) {
        my ( $number, $ldcolour, $label ) = split( /:/, $linedef, 3 );
        push( @rrd_negatives,
          "HRULE:" . $number . ( $ldcolour ? "#$ldcolour" : $colour ) );

      } elsif ( $node->{client}->{$service}->{"$negfield.warn"} ) {
        push(
          @rrd_negatives,
          "HRULE:"
            . $node->{client}->{$service}->{
            $node->{client}->{$service}->{ $field . ".negative" } . ".warn"
            }
            . ( defined $single_value and $single_value )
          ? "#ff0000"
          : $colour
        );
      }

      push( @rrd, "GPRINT:c$negfield:LAST:$rrdformat" . $rrdscale . "/\\g" );
      push( @rrd, "GPRINT:c$rrdname:LAST:$rrdformat" . $rrdscale . "" );
      push( @rrd, "GPRINT:i$negfield:MIN:$rrdformat" . $rrdscale . "/\\g" );
      push( @rrd, "GPRINT:i$rrdname:MIN:$rrdformat" . $rrdscale . "" );
      push( @rrd,
        "GPRINT:g$negfield:AVERAGE:$avgformat" . $rrdscale . "/\\g" );
      push( @rrd, "GPRINT:g$rrdname:AVERAGE:$avgformat" . $rrdscale . "" );
      push( @rrd, "GPRINT:a$negfield:MAX:$rrdformat" . $rrdscale . "/\\g" );
      push( @rrd, "GPRINT:a$rrdname:MAX:$rrdformat" . $rrdscale . "\\j" );
      push( @{ $total_pos{'min'} }, "i$rrdname" );
      push( @{ $total_pos{'avg'} }, "g$rrdname" );
      push( @{ $total_pos{'max'} }, "a$rrdname" );
      push( @{ $total_neg{'min'} }, "i$negfield" );
      push( @{ $total_neg{'avg'} }, "g$negfield" );
      push( @{ $total_neg{'max'} }, "a$negfield" );
    } else {
      push( @rrd, "COMMENT: Cur" . $self->rrdkludge . ":" )
        unless $global_headers;
      push( @rrd, "GPRINT:c$rrdname:LAST:$rrdformat" . $rrdscale . "" );
      push( @rrd, "COMMENT: Min" . $self->rrdkludge . ":" )
        unless $global_headers;
      push( @rrd, "GPRINT:i$rrdname:MIN:$rrdformat" . $rrdscale . "" );
      push( @rrd, "COMMENT: Avg" . $self->rrdkludge . ":" )
        unless $global_headers;
      push( @rrd, "GPRINT:g$rrdname:AVERAGE:$avgformat" . $rrdscale . "" );
      push( @rrd, "COMMENT: Max" . $self->rrdkludge . ":" )
        unless $global_headers;
      push( @rrd, "GPRINT:a$rrdname:MAX:$rrdformat" . $rrdscale . "\\j" );
      push( @{ $total_pos{'min'} }, "i$rrdname" );
      push( @{ $total_pos{'avg'} }, "g$rrdname" );
      push( @{ $total_pos{'max'} }, "a$rrdname" );
    }

    # Draw HRULEs
    my $linedef =
      $self->node->config->get( "line", undef, $domain, $name, $service,
      $field );
    if ($linedef) {
      my ( $number, $ldcolour, $label ) = split( /:/, $linedef, 3 );
      $label =~ s/:/\\:/g if defined $label;
      push(
        @rrd,
        "HRULE:" . $number
          . (
          $ldcolour ? "#$ldcolour"
          : (
            ( defined $single_value and $single_value ) ? "#ff0000"
            : $colour
          )
          )
          . ( ( defined $label and length($label) ) ? ":$label" : "" ),
        "COMMENT: \\j"
      );
    } elsif ( $node->{client}->{$service}->{"$field.warn"} ) {
      push( @rrd,
            "HRULE:"
          . $node->{client}->{$service}->{"$field.warn"}
          . ( $single_value ? "#ff0000" : $colour ) );
    }
  }

  if (@rrd_negatives) {
    push( @rrd, @rrd_negatives );
    push( @rrd, "LINE2:re_zero#000000" );    # Redraw zero.
    if (  exists $node->{client}->{$service}->{graph_total}
      and exists $total_pos{'min'}
      and exists $total_neg{'min'}
      and @{ $total_pos{'min'} }
      and @{ $total_neg{'min'} } ) {

      push( @rrd,
            "CDEF:ipostotal="
          . join( ",", map { "$_,UN,0,$_,IF" } @{ $total_pos{'min'} } )
          . ( ",+" x ( @{ $total_pos{'min'} } - 1 ) ) );
      push( @rrd,
            "CDEF:gpostotal="
          . join( ",", map { "$_,UN,0,$_,IF" } @{ $total_pos{'avg'} } )
          . ( ",+" x ( @{ $total_pos{'avg'} } - 1 ) ) );
      push( @rrd,
            "CDEF:apostotal="
          . join( ",", map { "$_,UN,0,$_,IF" } @{ $total_pos{'max'} } )
          . ( ",+" x ( @{ $total_pos{'max'} } - 1 ) ) );
      push( @rrd,
            "CDEF:inegtotal="
          . join( ",", map { "$_,UN,0,$_,IF" } @{ $total_neg{'min'} } )
          . ( ",+" x ( @{ $total_neg{'min'} } - 1 ) ) );
      push( @rrd,
            "CDEF:gnegtotal="
          . join( ",", map { "$_,UN,0,$_,IF" } @{ $total_neg{'avg'} } )
          . ( ",+" x ( @{ $total_neg{'avg'} } - 1 ) ) );
      push( @rrd,
            "CDEF:anegtotal="
          . join( ",", map { "$_,UN,0,$_,IF" } @{ $total_neg{'max'} } )
          . ( ",+" x ( @{ $total_neg{'max'} } - 1 ) ) );
      push( @rrd, "CDEF:dpostotal=ipostotal,UN,ipostotal,UNKN,IF" );
      push(
        @rrd,
        "LINE1:dpostotal#000000:" . $node->{client}->{$service}->{graph_total}
          . (
          " " x (
            $max_field_len -
              length( $node->{client}->{$service}->{graph_total} ) + 1
          )
          )
      );
      push( @rrd, "GPRINT:gnegtotal:LAST:$rrdformat" . $rrdscale . "/\\g" );
      push( @rrd, "GPRINT:gpostotal:LAST:$rrdformat" . $rrdscale . "" );
      push( @rrd, "GPRINT:inegtotal:MIN:$rrdformat" . $rrdscale . "/\\g" );
      push( @rrd, "GPRINT:ipostotal:MIN:$rrdformat" . $rrdscale . "" );
      push( @rrd,
        "GPRINT:gnegtotal:AVERAGE:$avgformat" . $rrdscale . "/\\g" );
      push( @rrd, "GPRINT:gpostotal:AVERAGE:$avgformat" . $rrdscale . "" );
      push( @rrd, "GPRINT:anegtotal:MAX:$rrdformat" . $rrdscale . "/\\g" );
      push( @rrd, "GPRINT:apostotal:MAX:$rrdformat" . $rrdscale . "\\j" );
    }
  } elsif ( exists $node->{client}->{$service}->{graph_total}
    and exists $total_pos{'min'}
    and @{ $total_pos{'min'} } ) {
    push( @rrd,
          "CDEF:ipostotal="
        . join( ",", map { "$_,UN,0,$_,IF" } @{ $total_pos{'min'} } )
        . ( ",+" x ( @{ $total_pos{'min'} } - 1 ) ) );
    push( @rrd,
          "CDEF:gpostotal="
        . join( ",", map { "$_,UN,0,$_,IF" } @{ $total_pos{'avg'} } )
        . ( ",+" x ( @{ $total_pos{'avg'} } - 1 ) ) );
    push( @rrd,
          "CDEF:apostotal="
        . join( ",", map { "$_,UN,0,$_,IF" } @{ $total_pos{'max'} } )
        . ( ",+" x ( @{ $total_pos{'max'} } - 1 ) ) );

    push( @rrd, "CDEF:dpostotal=ipostotal,UN,ipostotal,UNKN,IF" );
    push(
      @rrd,
      "LINE1:dpostotal#000000:" . $node->{client}->{$service}->{graph_total}
        . (
        " " x (
          $max_field_len -
            length( $node->{client}->{$service}->{graph_total} ) + 1
        )
        )
    );
    push( @rrd, "COMMENT: Cur" . $self->rrdkludge . ":" )
      unless $global_headers;
    push( @rrd, "GPRINT:gpostotal:LAST:$rrdformat" . $rrdscale . "" );
    push( @rrd, "COMMENT: Min" . $self->rrdkludge . ":" )
      unless $global_headers;
    push( @rrd, "GPRINT:ipostotal:MIN:$rrdformat" . $rrdscale . "" );
    push( @rrd, "COMMENT: Avg" . $self->rrdkludge . ":" )
      unless $global_headers;
    push( @rrd, "GPRINT:gpostotal:AVERAGE:$avgformat" . $rrdscale . "" );
    push( @rrd, "COMMENT: Max" . $self->rrdkludge . ":" )
      unless $global_headers;
    push( @rrd, "GPRINT:apostotal:MAX:$rrdformat" . $rrdscale . "\\j" );
  }

  foreach my $time ( keys(%times) ) {
    next unless ( $self->draw->{$time} );
    my @complete = ();
    if ( $self->rrdkludge ) {
      push( @complete,
        '--font',
        'LEGEND:7:/Users/adam/src/sandbox/moonin/extra/VeraMono.ttf',
        '--font',
        'UNIT:7:/Users/adam/src/sandbox/moonin/extra/VeraMono.ttf',
        '--font',
        'AXIS:7:/Users/adam/src/sandbox/moonin/extra/VeraMono.ttf' );
    }

    $self->log->debug("Processing $name -> $time");

    # Do the header (title, vtitle, size, etc...)
    push @complete, @{ $self->_get_header( $service, $time ) };
    if ( $self->linekludge ) {
      @rrd = map { s/LINE3:/LINE2.2:/; $_; } @rrd;
      @rrd = map { s/LINE2:/LINE1.6:/; $_; } @rrd;

      # LINE1 is thin enough.
    }
    push @complete, @rrd;

    push( @complete,
          "COMMENT:Last update"
        . $self->rrdkludge . ": "
        . $self->_RRDescape( scalar localtime($lastupdate) )
        . "\\r" );

    if ( time - 300 < $lastupdate ) {
      push @complete, "--end",
        ( int( $lastupdate / $self->resolutions->{$time} ) ) *
        $self->resolutions->{$time};
    }
    $self->log->debug( "\n\nrrdtool \"graph\" \"",
      join( "\"\n\t\"", @complete ), "\"\n" );
    RRDs::graph(@complete);
    if ( my $ERROR = RRDs::error ) {
      $self->log->error("Unable to graph $filename: $ERROR");
    }
  }

  if ( $self->node->get_bool_val( $service, "graph_sums", 0 ) ) {
    foreach my $time ( keys %{ $self->sumtimes } ) {
      next unless ( $self->draw->{ "sum" . $time } );
      my @rrd_sum;
      push @rrd_sum, @{ $self->_get_header( $service, $time, 1 ) };

      if ( time - 300 < $lastupdate ) {
        push @rrd_sum, "--end",
          ( int( $lastupdate / $self->resolutions->{$time} ) ) *
          $self->resolutions->{$time};
      }
      push @rrd_sum, @rrd;
      push( @rrd_sum,
            "COMMENT:Last update"
          . $self->rrdkludge . ": "
          . $self->_RRDescape( scalar localtime($lastupdate) )
          . "\\r" );

      my $labelled = 0;
      my @defined  = ();
      for ( my $index = 0; $index <= $#rrd_sum; $index++ ) {
        if ( $rrd_sum[$index] =~ /^(--vertical-label|-v)$/ ) {
          ( my $label = $node->{client}->{$service}->{graph_vlabel} ) =~
            s/\$\{graph_period\}/$self->sumtimes->{$time}[0]/g;
          splice( @rrd_sum, $index, 2, ( "--vertical-label", $label ) );
          $index++;
          $labelled++;
        } elsif ( $rrd_sum[$index] =~
          /^(LINE[123]|STACK|AREA|GPRINT):([^#:]+)([#:].+)$/ ) {
          my ( $pre, $fname, $post ) = ( $1, $2, $3 );
          next if $fname eq "re_zero";
          if ( $post =~ /^:AVERAGE/ ) {
            splice( @rrd_sum, $index, 1, $pre . ":x$fname" . $post );
            $index++;
            next;
          }
          next if grep /^x$fname$/, @defined;
          push @defined, "x$fname";
          my @replace;

          if ( !defined( $node->{client}->{$service}->{ $fname . ".type" } )
            or $node->{client}->{$service}->{ $fname . ".type" } ne "GAUGE" )
          {
            if ( $time eq "week" ) {

     # Every plot is half an hour. Add two plots and multiply, to get per hour
              if ( $self->_graph_by_minute( $domain, $name, $service ) ) {

                # Already multiplied by 60
                push @replace,
"CDEF:x$fname=PREV($fname),UN,0,PREV($fname),IF,$fname,+,5,*,6,*";
              } else {
                push @replace,
"CDEF:x$fname=PREV($fname),UN,0,PREV($fname),IF,$fname,+,300,*,6,*";
              }
            } else {

              # Every plot is one day exactly. Just multiply.
              if ( $self->_graph_by_minute( $domain, $name, $service ) ) {

                # Already multiplied by 60
                push @replace, "CDEF:x$fname=$fname,5,*,288,*";
              } else {
                push @replace, "CDEF:x$fname=$fname,300,*,288,*";
              }
            }
          }
          push @replace, $pre . ":x$fname" . $post;
          splice( @rrd_sum, $index, 1, @replace );
          $index++;
        } elsif (
          $rrd_sum[$index] =~ /^(--lower-limit|--upper-limit|-l|-u)$/ ) {
          $index++;
          $rrd_sum[$index] =
            $rrd_sum[$index] * 300 * $self->sumtimes->{$time}->[1];
        }
      }

      unless ($labelled) {
        my $label = $node->{client}->{$service}->{"graph_vlabel_sum_$time"}
          || $self->sumtimes->{$time}->[0];
        unshift @rrd_sum, "--vertical-label", $label;
      }

      $self->log->debug( "\n\nrrdtool \"graph\" \"",
        join( "\"\n\t\"", @rrd_sum ), "\"\n" );
      RRDs::graph(@rrd_sum);

      if ( my $ERROR = RRDs::error ) {
        $self->log->error("Unable to graph $filename: $ERROR");
      }
    }
  }

  $service_time = sprintf( "%.2f", ( Time::HiRes::time - $service_time ) );
  $self->log->debug("Graphed service : $service ($service_time sec * 4)");

  # print STATS "GS|$domain|$name|$service|$service_time\n"
  #   unless $skip_stats;

  foreach (@added) {
    delete $node->{client}->{$service}->{$_}
      if exists $node->{client}->{$service}->{$_};
  }
  @added = ();

}

sub _RRDescape {
  my $self = shift;
  my $text = shift;
  return $RRDs::VERSION < 1.2 ? $text : $self->_escape($text);
}

1;
