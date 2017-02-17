package NGCP::Panel::Utils::DataHal;

use Moo;
extends 'Data::HAL';

#TODO: read parameters from the ngcp-panel config section if we will use more API format configs
#use MooseX::Configuration;
around 'BUILDARGS' => sub {
    my $orig  = shift;
    my $class = shift;
    my $params;
    if ((scalar @_) == 1) {
        ($params) = @_;
    } else {
        $params = { @_ };
    }
    if( !defined $params->{forcearray_underneath} && !defined $params->{_forcearray_underneath} ){
        $params->{_forcearray_underneath} = { embedded => 1 };
    }
    $class->$orig($params);
};

1;
