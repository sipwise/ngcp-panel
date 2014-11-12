package NGCP::Panel::Utils::DeviceBootstrap;


use strict;
use Data::Dumper;
use NGCP::Panel::Utils::DeviceBootstrap::RPC;
use NGCP::Panel::Utils::DeviceBootstrap::Panasonic;

#NGCP::Panel::Utils::DeviceBootstrap::RPC params =>
    #$params = {
    #    redirect_uri
    #    redirect_uri_params
    #    mac
    #    mac_old (optional)
    #    c for log, config sync uri from config
    #    credentials => {user=>, password=>}
    #};

sub dispatch{
    my($c, $action, $fdev, $old_identifier) = @_;
    
    my $device = $fdev->profile->config->device;
    my $credentials = $fdev->profile->config->device->autoprov_redirect_credentials;
    my $vcredentials;
    if($credentials){
        $vcredentials = { map { $_ => $credentials->$_ } qw/user password/};
    }

    my $sync_params_rs = $device->autoprov_sync->search_rs({
        'autoprov_sync_parameters.parameter_name' => 'sync_params',
    },{
        join   => 'autoprov_sync_parameters',
        select => ['me.parameter_value'],
    });
    my $sync_params = $sync_params_rs->first ? $sync_params_rs->first->parameter_value : '';
    my $params = {
        c => $c,
        mac => $fdev->identifier,
        mac_old => $old_identifier,
        bootstrap_method => $device->bootstrap_method,
        redirect_uri_params => $sync_params,
        credentials => $vcredentials,
    };
    my $redirect_processor = get_redirect_processor($params);
    my $ret;
    if($redirect_processor){
        $ret = $redirect_processor->redirect_server_call($action);
    }
    return $ret;
}
sub get_redirect_processor{
    my ($params) = @_;
    my $c = $params->{c};
    my $bootstrap_method = $params->{bootstrap_method};
    $c->log->debug( "bootstrap_method=$bootstrap_method;" );
    my $redirect_processor;
    if('redirect_panasonic' eq $bootstrap_method){
        $redirect_processor = NGCP::Panel::Utils::DeviceBootstrap::Panasonic->new( params => $params );
    }elsif('redirect_yealink' eq $bootstrap_method){
        $redirect_processor = NGCP::Panel::Utils::DeviceBootstrap::yealink->new( params => $params );
    }elsif('http' eq $bootstrap_method){
        #$ret = panasonic_bootstrap_register($params);
    }
    return $redirect_processor;
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
1;

=head1 NAME

NGCP::Panel::Utils::DeviceBootstrap

=head1 DESCRIPTION

Make API requests to configure remote redirect servers for requested MAC with autorpov uri.

=head1 METHODS

=head2 bootstrap

Dispatch to proper vendor API call.

=head1 AUTHOR

Irina Peshinskaya C<< <ipeshinskaya@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
