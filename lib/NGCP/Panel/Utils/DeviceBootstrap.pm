package NGCP::Panel::Utils::DeviceBootstrap;


use strict;
use warnings;

use Data::Dumper;
use NGCP::Panel::Utils::DeviceBootstrap::VendorRPC;
use NGCP::Panel::Utils::DeviceBootstrap::Panasonic;
use NGCP::Panel::Utils::DeviceBootstrap::Yealink;
use NGCP::Panel::Utils::DeviceBootstrap::Polycom;
use NGCP::Panel::Utils::DeviceBootstrap::Snom;
use NGCP::Panel::Utils::DeviceBootstrap::Grandstream;
use NGCP::Panel::Utils::DeviceBootstrap::ALE;

my $redirect_processor;

sub get_cached_redirect_processor{
    return $redirect_processor;
}

sub dispatch{
    my($c, $action, $fdev, $old_identifier) = @_;

    if($c->config->{deviceprovisioning}->{skip_vendor_redirect}) {
        $c->log->info("skipping '$action', disabled by configuration");
        return;
    }

    my $params = {
        %{get_devmod_params($c, $fdev->profile->config->device)},
        mac => $fdev->identifier,
        mac_old => $old_identifier,
    };
    return _dispatch($c, $action, $params);
}

sub dispatch_devmod{
    my($c, $action, $devmod) = @_;

    if($c->config->{deviceprovisioning}->{skip_vendor_redirect}) {
        $c->log->info("skipping '$action', disabled by configuration");
        return;
    }

    my $params = get_devmod_params($c,$devmod);
    return _dispatch($c, $action, $params);
}

sub _dispatch{
    my($c, $action, $params) = @_;
    $redirect_processor = get_redirect_processor($params);
    my $err;
    if($redirect_processor){
        $c->log->debug( "action=$action;" );
        if($redirect_processor->can($action)){
            $err = $redirect_processor->$action();
        }else{
            if( ('register' eq $action) && $params->{mac_old} && ( $params->{mac_old} ne $params->{mac} ) ){
                $redirect_processor->redirect_server_call('unregister');
            }
            $err = $redirect_processor->redirect_server_call($action);
        }
        $c->log->debug( "err=$err;" );
    }
    return $err;
}

sub get_devmod_params{
    my($c, $devmod) = @_;

    my $credentials = $devmod->autoprov_redirect_credentials;
    my $vcredentials;
    if($credentials){
        $vcredentials = { map { $_ => $credentials->$_ } qw/user password/};
    }

    my $sync_params_rs = $devmod->autoprov_sync->search_rs({
            'autoprov_sync_parameters.bootstrap_method' => $devmod->bootstrap_method,
        },{
            join      => 'autoprov_sync_parameters',
        }
    );
    my $sync_params={};
    foreach($sync_params_rs->all){
        $sync_params->{$_->autoprov_sync_parameters->parameter_name()} = $_->parameter_value;
    }
    my $params = {
        c => $c,
        bootstrap_method => $devmod->bootstrap_method,
        redirect_uri => $devmod->bootstrap_uri,
        redirect_params => $sync_params,
        credentials => $vcredentials,
        vendor => $devmod->vendor,
    };
    return $params;
}

sub get_redirect_processor{
    my ($params) = @_;
    my $c = $params->{c};
    my $bootstrap_method = $params->{bootstrap_method};
    my $redirect_processor;
    if('redirect_panasonic' eq $bootstrap_method){
        $redirect_processor = NGCP::Panel::Utils::DeviceBootstrap::Panasonic->new( params => $params );
    }elsif('redirect_yealink' eq $bootstrap_method){
        $redirect_processor = NGCP::Panel::Utils::DeviceBootstrap::Yealink->new( params => $params );
    }elsif('redirect_polycom' eq $bootstrap_method){
        $redirect_processor = NGCP::Panel::Utils::DeviceBootstrap::Polycom->new( params => $params );
    }elsif('redirect_snom' eq $bootstrap_method){
        $redirect_processor = NGCP::Panel::Utils::DeviceBootstrap::Snom->new( params => $params );
    }elsif('redirect_grandstream' eq $bootstrap_method){
        $redirect_processor = NGCP::Panel::Utils::DeviceBootstrap::Grandstream->new( params => $params );
    }elsif('redirect_ale' eq $bootstrap_method){
        $redirect_processor = NGCP::Panel::Utils::DeviceBootstrap::ALE->new( params => $params );
    }elsif('http' eq $bootstrap_method){
        #$ret = panasonic_bootstrap_register($params);
    }
    elsif('none' eq $bootstrap_method){
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

sub devmod_sync_parameters_prefetch_api{
    my($c,$item,$resource) = @_;
    $resource //= {};
    my $schema = $c->model('DB');
    my $bootstrap_method = $item->get_column('bootstrap_method');
    my $bootstrap_params_rs = $schema->resultset('autoprov_sync')->search_rs({
        'autoprov_sync_parameters.bootstrap_method' => $bootstrap_method,
        'me.device_id' => $item->id,
    },{
        join => 'autoprov_sync_parameters',
        select => [qw/autoprov_sync_parameters.parameter_name me.parameter_value/],
        as => [qw/parameter_name parameter_value/]
    });
    foreach ($bootstrap_params_rs->all){
        my $param_name = 'bootstrap_config_'.$bootstrap_method.'_'.$_->get_column('parameter_name');
        $resource->{$param_name} = $_->parameter_value;
    }
    return $resource;
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
        delete $credentials->{device_id};
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
        $sync_parameter->{device_id} ||= $devmod ? $devmod->id : undef;
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
