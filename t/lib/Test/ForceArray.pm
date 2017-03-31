package Test::ForceArray;

use strict;
use Exporter qw'import';

our @EXPORT      = qw//;
our @EXPORT_OK   = qw/&get_embedded_item &get_embedded_forcearray &get_id_from_hal/;
our %EXPORT_TAGS = ( 
    DEFAULT => [qw/&get_embedded_item &get_embedded_forcearray &get_id_from_hal/],
    all    =>  [qw/&get_embedded_item &get_embedded_forcearray &get_id_from_hal/]
);

sub get_embedded_item{
    my($hal,$name) = @_;
    my $embedded = $hal->{_embedded}->{'ngcp:'.$name} ;
    return 'ARRAY' eq ref $embedded ? $embedded->[0] : $embedded ;
}

sub get_embedded_forcearray{
    my($hal,$name) = @_;
    my $embedded = $hal->{_embedded}->{'ngcp:'.$name} ;
    return 'ARRAY' eq ref $embedded ? $embedded : [ $embedded ];
}

sub get_id_from_hal{
    my($hal,$name) = @_;
    my $embedded = get_embedded_item($hal,$name);
    (my ($id)) = $embedded->{_links}{self}{href} =~ m!${name}/([0-9]*)$! if $embedded;
    return $id;
}

1;