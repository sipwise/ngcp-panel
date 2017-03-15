package NGCP::Panel::Utils::DataHal;

use Moo;
use NGCP::Panel;
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
    my $config = $params->{config};
    if(!$config){
        $config = NGCP::Panel::get_panel_config();
    }
    if(!defined $params->{forcearray_underneath} && !defined $params->{_forcearray_underneath} ){
        my $embedded_forcearray = $config->{appearance}->{api_embedded_forcearray} // 0;
        $params->{_forcearray_underneath} = { 
            embedded => $embedded_forcearray,
        };
    }
    $class->$orig($params);
};

1;
