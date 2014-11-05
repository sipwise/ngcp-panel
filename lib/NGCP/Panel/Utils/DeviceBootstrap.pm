package NGCP::Panel::Utils::DeviceBootstrap;

use Sipwise::Base;
use NGCP::Panel::Utils::DeviceBootstrap::Panasonic;

sub get_baseuri {
    my ($c) = @_;

    my $uri = 
        ($c->config->{deviceprovisioning}->{secure} ? 'https' : 'http').
        '://'.
        ($c->config->{deviceprovisioning}->{host} // $c->req->uri->host).
        ':'.
        ($c->config->{deviceprovisioning}->{port} // 1444).
        '/device/autoprov/config/';

    return $uri;
}

sub dispatch {
    my ($c, $action, $dev, $old_mac) = @_;

    my $btype = $dev->profile->config->device->bootstrap_method;
    my $mod = 'NGCP::Panel::Utils::DeviceBootstrap';

    if($btype eq 'redirect_panasonic') {
        $mod .= '::Panasonic';
    } elsif($btype eq 'http') {
        return;
    } else {
        return;
    }

    $mod .= '::'.$action;
    $c->log->debug("dispatching bootstrap call to '$mod'");
    no strict "refs";
    return $mod->($c, $dev, $dev->identifier, $old_mac);
}

sub devmod_sync_parameters_prefetch{
    my($c,$devmod,$params) = @_;
    my $schema = $c->model('DB');
    my $bootstrap_method = $params->{'bootstrap_method'};
    my $bootstrap_params_rs = $schema->resultset('autoprov_sync_parameters')->search_rs({
        'me.bootstrap_method' => $bootstrap_method,
    });
    my @parameters = ();
    foreach ($bootstrap_params_rs->all){
        my $sync_parameter = {
            device_id       => $devmod ? $devmod->id : undef,
            parameter_id    => $_->id,
            parameter_value => delete $params->{'bootstrap_config_'.$bootstrap_method.'_'.$_->parameter_name},
        };
        push @parameters,$sync_parameter;
    }
    return \@parameters;
}
sub devmod_sync_credentials_prefetch{
    my($c,$devmod,$params) = @_;
    my $schema = $c->model('DB');
    my $bootstrap_method = $params->{'bootstrap_method'};
    my $credentials = {
        device_id       => $devmod ? $devmod->id : undef,
    };
    foreach (qw/user password/){
        $credentials->{$_} = delete $params->{'bootstrap_config_'.$bootstrap_method.'_'.$_};
    }
    return $credentials;
}
sub devmod_sync_credentials_store{
    my($c,$devmod,$credentials) = @_;
    my $schema = $c->model('DB');
    my $credentials_rs = $schema->resultset('autoprov_redirect_credentials')->search_rs({
        'device_id' => $devmod->id
    });
    if(!$credentials_rs->first){
        $credentials->{device_id} = $devmod->id;
        $schema->resultset('autoprov_redirect_credentials')->create($credentials);    
    }else{
       $credentials_rs->update($credentials);
    }
}

sub devmod_sync_clear {
    my($c,$params) = @_;
    foreach (keys %$params){
        if($_ =~/^bootstrap_config_/i){
            delete $params->{$_};
        }
    }
}
sub devmod_sync_parameters_store {
    my($c,$devmod,$sync_parameters) = @_;
    my $schema = $c->model('DB');
    foreach my $sync_parameter (@$sync_parameters){
        $sync_parameter->{device_id} ||= $devmod ? $devmod->id : undef
        $schema->resultset('autoprov_sync')->create($sync_parameter);
    }
}
