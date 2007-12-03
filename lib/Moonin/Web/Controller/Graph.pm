package Moonin::Web::Controller::Graph;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Date::Manip;
use IO::File;
use POSIX qw(strftime);

=head1 NAME

Moonin::Web::Controller::Graph - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

sub index : Private {
  my ( $self, $c ) = @_;

  $c->response->body('Matched Moonin::Web::Controller::Graph in Graph.');
}

sub draw : Regex('graph/(.+?)/(.+?)/(.+?)/(.+).png') {
  my ( $self, $c, ) = @_;
  my ( $domain, $name, $service, $scale ) = @{ $c->req->captures };
  $c->log->debug("$domain, $name, $service, $scale");
  my %period = (
    "day"      => 300,
    "week"     => 1800,
    "month"    => 7200,
    "year"     => 86400,
    "week-sum" => 1800,
    "year-sum" => 86400
  );
  my @SCALES = qw(day week month year week-sum year-sum);
  my $time   = time;
  my $filename =
    $self->get_picture_filename( $c, $domain, $name, $service, $scale );
  my $build_graphs = 0;
  if ( -f $filename ) {
    $c->log->debug("I exist");
    my @sstats = stat($filename);
    my $slast_modified =
      strftime( "%a, %d %b %Y %H:%M:%S %Z", localtime( $sstats[9] ) );
    $c->log->debug("I have a $slast_modified");
    my $modified_since = $c->req->header('If-Modified-Since');
    $c->log->debug("I have $modified_since");
    if ( defined $modified_since
      and !&modified( $modified_since, $sstats[9] - 1 ) ) {
      $c->res->status(304);
      $c->res->content_type('image/png');
      $c->res->header(
        'Expires' => strftime(
          "%a, %d %b %Y %H:%M:%S GMT",
          gmtime( time + ( $period{$scale} - ( $time % $period{$scale} ) ) )
        )
      );
      $c->res->header( 'Cache-Control' => "max-age=240" );
      $c->res->header( 'Last-Modified' => $slast_modified );
      return 1;
    }
  }
  #$c->model( 'Graph', $domain, $name )->process( $service, $scale );
  $c->log->debug("This is my $filename");
  my @stats = stat($filename);
  my $last_modified =
    strftime( "%a, %d %b %Y %H:%M:%S %Z", localtime( $stats[9] ) );
  $c->res->status(200);
  $c->res->content_type('image/png');
  $c->res->header(
    'Expires' => strftime(
      "%a, %d %b %Y %H:%M:%S GMT",
      gmtime( time + ( $period{$scale} - ( $time % $period{$scale} ) ) )
    )
  );
  $c->res->header( 'Cache-Control' => "max-age=240" );
  $c->res->header( 'Last-Modified' => $last_modified );
  my $fh = IO::File->new( $filename, 'r' );

  if ( defined $fh ) {
    binmode $fh;
    $c->res->body($fh);
  } else {
    Catalyst::Exception->throw(
      message => "Unable to open $filename for reading" );
  }
  return 1;
}

sub modified {

  # Format of since_string If-Modified-Since: Wed, 23 Jun 2004 16:11:06 GMT

  my $since_string = shift;
  my $created      = shift;
  my $ifmodsec     = &UnixDate( &ParseDateString($since_string), "%s" );

  print STDERR "$ifmodsec < $created\n";
  return 1 if ( $ifmodsec < $created );
  return 0;
}

sub get_picture_filename {
  my $self    = shift;
  my $c       = shift;
  my $domain  = shift;
  my $name    = shift;
  my $service = shift;
  my $scale   = shift;

  return $c->model("Config")->htmldir . "/$domain/$name-$service-$scale.png";
}

=head1 AUTHOR

Adam Jacob

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
