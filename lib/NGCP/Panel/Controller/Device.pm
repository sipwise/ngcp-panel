package NGCP::Panel::Controller::Device;
use Sipwise::Base;

use Template;
use Crypt::Rijndael;
use JSON qw(decode_json encode_json);
use NGCP::Panel::Form::Device::Model;
use NGCP::Panel::Form::Device::ModelAdmin;
use NGCP::Panel::Form::Device::Firmware;
use NGCP::Panel::Form::Device::Config;
use NGCP::Panel::Form::Device::Profile;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DeviceBootstrap;
use NGCP::Panel::Utils::Device;
use NGCP::Panel::Form::Customer::PbxFieldDeviceExtensions;

BEGIN { extends 'Catalyst::Controller'; }

sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub base :Chained('/') :PathPart('device') :CaptureArgs(0) {
    my ($self, $c) = @_;

    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);

    # TODO: move out fw/profile/config fetching to separate func to not 
    # load it for subscriber access?
    my $reseller_id;
    if($c->user->roles eq 'reseller') {
        $reseller_id = $c->user->reseller_id;
    } elsif($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') {
        $reseller_id = $c->user->voip_subscriber->contract->contact->reseller_id;
    }

    my $devmod_rs = $c->model('DB')->resultset('autoprov_devices')->search_rs(undef,{
            'columns' => [qw/id reseller_id type vendor model front_image_type mac_image_type num_lines bootstrap_method bootstrap_uri/],
	});
    $reseller_id and $devmod_rs = $devmod_rs->search({ reseller_id => $reseller_id });
    $c->stash->{devmod_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'type', search => 1, title => $c->loc('Type') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'vendor', search => 1, title => $c->loc('Vendor') },
        { name => 'model', search => 1, title => $c->loc('Model') },
    ]);
 
    my $devfw_rs = $c->model('DB')->resultset('autoprov_firmwares')->search_rs(undef,{'columns' => [qw/id device_id version filename/],
	});
    $reseller_id and $devfw_rs = $devfw_rs->search({
        'device.reseller_id' => $reseller_id,
    },{ 
        join => 'device',
    });
    $c->stash->{devfw_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'device.reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'device.vendor', search => 1, title => $c->loc('Device Vendor') },
        { name => 'device.model', search => 1, title => $c->loc('Device Model') },
        { name => 'filename', search => 1, title => $c->loc('Firmware File') },
        { name => 'version', search => 1, title => $c->loc('Version') },
    ]);

    my $devconf_rs = $c->model('DB')->resultset('autoprov_configs')->search_rs(undef,{'columns' => [qw/id device_id version content_type/],
	});
    $reseller_id and $devconf_rs = $devconf_rs->search({
        'device.reseller_id' => $reseller_id,
    }, { 
        join => 'device',
    });
    $c->stash->{devconf_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'device.reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'device.vendor', search => 1, title => $c->loc('Device Vendor') },
        { name => 'device.model', search => 1, title => $c->loc('Device Model') },
        { name => 'version', search => 1, title => $c->loc('Version') },
    ]);

    my $devprof_rs = $c->model('DB')->resultset('autoprov_profiles');
    $reseller_id and $devprof_rs = $devprof_rs->search({
        'device.reseller_id' => $reseller_id,
    }, { 
        join => { 'config' => 'device' },
    });
    $c->stash->{devprof_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'config.device.reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'config.device.vendor', search => 1, title => $c->loc('Device Vendor') },
        { name => 'config.device.model', search => 1, title => $c->loc('Device Model') },
#        { name => 'firmware.filename', search => 1, title => $c->loc('Firmware File') },
        { name => 'config.version', search => 1, title => $c->loc('Configuration Version') },
    ]);

    my $fielddev_rs = $c->model('DB')->resultset('autoprov_field_devices');
    $reseller_id and $fielddev_rs = $fielddev_rs->search({
        'device.reseller_id' => $reseller_id,
    },{ 
        join => { 'profile' => { 'config' => 'device' } },
    });
    $c->stash->{fielddev_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'identifier', search => 1, title => $c->loc('MAC Address / Identifier') },
        { name => 'profile.name', search => 1, title => $c->loc('Profile Name') },
        { name => 'contract.id', search => 1, title => $c->loc('Customer #') },
        { name => 'contract.contact.email', search => 1, title => $c->loc('Customer Email') },
    ]);

    my $extensions_rs = $c->model('DB')->resultset('autoprov_devices')->search_rs({
        'type' => 'extension',
    });
    $reseller_id and $extensions_rs = $extensions_rs->search({ reseller_id => $reseller_id });
    
    $c->stash->{fielddev_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'identifier', search => 1, title => $c->loc('MAC Address / Identifier') },
        { name => 'profile.name', search => 1, title => $c->loc('Profile Name') },
        { name => 'contract.id', search => 1, title => $c->loc('Customer #') },
        { name => 'contract.contact.email', search => 1, title => $c->loc('Customer Email') },
    ]);

    $c->stash(
        devmod_rs     => $devmod_rs,
        devfw_rs      => $devfw_rs,
        devconf_rs    => $devconf_rs,
        devprof_rs    => $devprof_rs,
        fielddev_rs   => $fielddev_rs,
        extensions_rs => $extensions_rs,
        reseller_id   => $reseller_id,
        template      => 'device/list.tt',
    );
}

sub root :Chained('base') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub devmod_ajax :Chained('base') :PathPart('model/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{devmod_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{devmod_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub devmod_create :Chained('base') :PathPart('model/create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Device::ModelAdmin->new;
    } else {
        $form = NGCP::Panel::Form::Device::Model->new;
    }

    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    if($posted) {
        $c->req->params->{front_image} = $c->req->upload('front_image');
        $c->req->params->{mac_image} = $c->req->upload('mac_image');
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                if($c->user->is_superuser) {
                    $form->values->{reseller_id} = $form->values->{reseller}{id};
                } else {
                    $form->values->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->values->{reseller};

                my $ft = File::Type->new();
                foreach(qw/front_image mac_image/){
                    if($form->values->{$_}) {
                        my $image = delete $form->values->{$_};
                        $form->values->{$_} = $image->slurp;
                        $form->values->{$_.'_type'} = $ft->mime_type($form->values->{$_});
                    }
                }
                my $connectable_models = delete $form->values->{connectable_models};
                my $linerange = delete $form->values->{linerange};
                
                my $sync_parameters = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_prefetch($c, undef, $form->values);
                my $credentials = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_prefetch($c, undef, $form->values);
                NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_clear($c, $form->values);
                my $devmod = $schema->resultset('autoprov_devices')->create($form->values);
                NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_store($c, $devmod, $credentials);
                NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_store($c, $devmod, $sync_parameters);
                NGCP::Panel::Utils::DeviceBootstrap::dispatch_devmod($c, 'register_model', $devmod);
                NGCP::Panel::Utils::Device::process_connectable_models($c, 1, $devmod, decode_json($connectable_models) );
                
                foreach my $range(@{ $linerange }) {
                    delete $range->{id};
                    $range->{num_lines} = @{ $range->{keys} }; # backward compatibility
                    my $keys = delete $range->{keys};
                    my $r = $devmod->autoprov_device_line_ranges->create($range);
                    my $i = 0;
                    foreach my $label(@{ $keys }) {
                        $label->{line_index} = $i++;
                        $label->{position} = delete $label->{labelpos};
                        delete $label->{id};
                        $r->annotations->create($label);
                    }
                }
                delete $c->session->{created_objects}->{reseller};
                $c->session->{created_objects}->{device} = { id => $devmod->id };
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully created device model'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to create device model'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devmod_create_flag => 1,
        form => $form,
    );
}
sub prepare_connectable {
    my ($self, $c, $model) = @_;
    my $values = [];

    my $connected_rs = $c->model('DB')->resultset('autoprov_device_extensions')->search_rs({
        ( $model->type eq 'phone' ? 'device_id' : 'extension_id' ) => $model->id,
    });
    for my $connected($connected_rs->all) {
        push @$values, $connected->get_column ( $model->type eq 'phone' ? 'extension_id' : 'device_id' ) ;
    }
    return (encode_json($values), $values);
}

sub devmod_base :Chained('base') :PathPart('model') :CaptureArgs(1) {
    my ($self, $c, $devmod_id) = @_;

    unless($devmod_id->is_int) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid device model id '$devmod_id'",
            desc => $c->loc('Invalid device model id'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
    my $devmod = $c->stash->{devmod_rs}->find($devmod_id,{'+columns' => [qw/mac_image front_image/]});
    unless($devmod) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "device model with id '$devmod_id' not found",
            desc => $c->loc('Device model not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
    $c->stash(
        devmod => $devmod,
    );
}

sub devmod_delete :Chained('devmod_base') :PathPart('delete') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devmod}->delete;
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { id => $c->stash->{devmod}->id,
                      model => $c->stash->{devmod}->model,
                      vendor => $c->stash->{devmod}->vendor },
            desc => $c->loc('Device model successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete device model with id '".$c->stash->{devmod}->id."': $e",
            desc => $c->loc('Failed to delete device model'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
}

sub devmod_edit :Chained('devmod_base') :PathPart('edit') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $c->stash->{devmod}->get_inflated_columns };
    $params->{linerange} = [];
    foreach my $range($c->stash->{devmod}->autoprov_device_line_ranges->all) {
        my $keys = [];
        foreach my $key($range->annotations->all) {
            push @{ $keys }, { x => $key->x, y => $key->y, labelpos => $key->position };
        }
        my $r = { $range->get_inflated_columns };
        $r->{keys} = $keys;
        push @{ $params->{linerange} }, $r;
    }    
    #TODO: TO inflate/deflate, I think
    foreach ( $c->model('DB')->resultset('autoprov_sync')->search_rs({
        device_id =>$c->stash->{devmod}->id,
    })->all ){
        $params->{'bootstrap_config_'.$c->stash->{devmod}->bootstrap_method.'_'.$_->autoprov_sync_parameters->parameter_name} = $_->parameter_value;
    }
    my $credentials_rs = $c->model('DB')->resultset('autoprov_redirect_credentials')->search_rs({
        'me.device_id' => $c->stash->{devmod}->id,
    });
    if($credentials_rs->first){
        foreach ( qw/user password/ ){
            $params->{'bootstrap_config_'.$c->stash->{devmod}->bootstrap_method.'_'.$_} = $credentials_rs->first->get_column($_);
        }
    }
    #edit specific
    ($params->{connectable_models}) = $self->prepare_connectable($c, $c->stash->{devmod});

    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    $c->stash(edit_model => 1); # to make front_image optional
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Device::ModelAdmin->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::Device::Model->new(ctx => $c);
    }
    if($posted) {
        $c->req->params->{front_image} = $c->req->upload('front_image');
        $c->req->params->{mac_image} = $c->req->upload('mac_image');
    }

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                if($c->user->is_superuser) {
                    $form->values->{reseller_id} = $form->values->{reseller}{id};
                } else {
                    $form->values->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->values->{reseller};

                foreach (qw/front_image mac_image/){
                    if($form->values->{$_}) {
                        my $image = delete $form->values->{$_};
                        $form->values->{$_} = $image->slurp;
                        $form->values->{$_.'_type'} = $image->type;
                    } else {
                        delete $form->values->{$_};
                        delete $form->values->{$_.'_type'};
                    }
                }
                
                my $linerange = delete $form->values->{linerange};
                my $connectable_models = delete $form->values->{connectable_models};
                my $sync_parameters = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_prefetch($c, $c->stash->{devmod}, $form->values);
                my $credentials = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_prefetch($c, $c->stash->{devmod}, $form->values);
                NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_clear($c, $form->values);
                
                $c->stash->{devmod}->update($form->values);
                
                NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_store($c, $c->stash->{devmod}, $credentials);
                $schema->resultset('autoprov_sync')->search_rs({
                    device_id => $c->stash->{devmod}->id,
                })->delete;
                NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_store($c, $c->stash->{devmod}, $sync_parameters);
                NGCP::Panel::Utils::DeviceBootstrap::dispatch_devmod($c, 'register_model', $c->stash->{devmod} );
                NGCP::Panel::Utils::Device::process_connectable_models($c, 0, $c->stash->{devmod}, decode_json($connectable_models) );
                
                my @existing_range = ();
                my $range_rs = $c->stash->{devmod}->autoprov_device_line_ranges;
                foreach my $range(@{ $linerange }) {
                    next unless(defined $range);
                    my $keys = delete $range->{keys};
                    $range->{num_lines} = @{ $keys }; # backward compatibility
                    my $old_range;
                    if(defined $range->{id}) {
                        # should be an existing range, do update
                        $old_range = $range_rs->find($range->{id});
                        delete $range->{id};
                        unless($old_range) {
                            $old_range = $range_rs->create($range);
                        } else {
                            # formhandler only passes set check-boxes, so explicitely unset here
                            $range->{can_private} //= 0;
                            $range->{can_shared} //= 0;
                            $range->{can_blf} //= 0;
                            $old_range->update($range);
                        }
                    } else {
                        # new range
                        $old_range = $range_rs->create($range);
                    }
                    $old_range->annotations->delete;
                    my $i = 0;
                    foreach my $label(@{ $keys }) {
                        next unless(defined $label);
                        $label->{line_index} = $i++;
                        $label->{position} = delete $label->{labelpos};
                        delete $label->{id};
                        $old_range->annotations->create($label);
                    }

                    push @existing_range, $old_range->id; # mark as valid (delete others later)

                    # delete field device line assignments with are out-of-range or use a
                    # feature which is not supported anymore after edit
                    foreach my $fielddev_line($c->model('DB')->resultset('autoprov_field_device_lines')
                        ->search({ linerange_id => $old_range->id })->all) {
                        if($fielddev_line->key_num >= $old_range->num_lines ||
                           ($fielddev_line->line_type eq 'private' && !$old_range->can_private) ||
                           ($fielddev_line->line_type eq 'shared' && !$old_range->can_shared) ||
                           ($fielddev_line->line_type eq 'blf' && !$old_range->can_blf)) {

                           $fielddev_line->delete;
                       }
                    }
                }
                # delete invalid range ids (e.g. removed ones)
                $range_rs->search({
                    id => { 'not in' => \@existing_range },
                })->delete_all;
                delete $c->session->{created_objects}->{reseller};
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                data => { id => $c->stash->{devmod}->id,
                          model => $c->stash->{devmod}->model,
                          vendor => $c->stash->{devmod}->vendor },
                desc => $c->loc('Successfully updated device model'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to update device model'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devmod_edit_flag => 1,
        form => $form,
    );
}
sub devmod_download_frontimage_by_profile :Chained('devprof_base') :PathPart('frontimage') :Args(0) {
    my ($self, $c) = @_;

    my $devprof = $c->stash->{devprof};
    my $devmod = $devprof->config->device;
    unless($devmod->front_image) {
        $c->response->body($c->loc('404 - No front image available for the model of this device profile'));
        $c->response->status(404);
        return;
    }
    $c->response->content_type($devmod->front_image_type);
    $c->response->body($devmod->front_image);
}

sub devmod_download_frontimage :Chained('devmod_base') :PathPart('frontimage') :Args(0) {
    my ($self, $c) = @_;

    my $devmod = $c->stash->{devmod};
    unless($devmod->front_image) {
        $c->response->body($c->loc('404 - No front image available for this device model'));
        $c->response->status(404);
        return;
    }
    $c->response->content_type($devmod->front_image_type);
    $c->response->body($devmod->front_image);
}

sub devmod_download_macimage :Chained('devmod_base') :PathPart('macimage') :Args(0) {
    my ($self, $c) = @_;

    my $devmod = $c->stash->{devmod};
    unless($devmod->mac_image) {
        $c->response->body($c->loc('404 - No mac image available for this device model'));
        $c->response->status(404);
        return;
    }
    $c->response->content_type($devmod->mac_image_type);
    $c->response->body($devmod->mac_image);
}

sub devfw_ajax :Chained('base') :PathPart('firmware/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{devfw_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{devfw_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub devfw_create :Chained('base') :PathPart('firmware/create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Device::Firmware->new;

    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    if($posted) {
        $c->req->params->{data} = $c->req->upload('data');
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'device.create' => $c->uri_for('/device/model/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $file = delete $form->values->{data};
                $form->values->{filename} = $file->filename;
                $form->values->{data} = $file->slurp;
                my $devmod = $c->stash->{devmod_rs}->find($form->values->{device}{id},{'+columns' => [qw/mac_image front_image/]});
                my $devfw = $devmod->create_related('autoprov_firmwares', $form->values);
                delete $c->session->{created_objects}->{device};
                $c->session->{created_objects}->{firmware} = { id => $devfw->id };
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully created device firmware'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to create device firmware'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devfw_create_flag => 1,
        form => $form,
    );
}

sub devfw_base :Chained('base') :PathPart('firmware') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c, $devfw_id) = @_;

    unless($devfw_id->is_int) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid device firmware id '$devfw_id'",
            desc => $c->loc('Invalid device firmware id'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devfw} = $c->stash->{devfw_rs}->find($devfw_id,{'+columns' => 'data'});
    unless($c->stash->{devfw}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "device firmware with id '$devfw_id' not found",
            desc => $c->loc('Device firmware not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
}

sub devfw_delete :Chained('devfw_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devfw}->delete;
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{devfw}->get_inflated_columns },
            desc => $c->loc('Device firmware successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete device firmware with id '".$c->stash->{devfw}->id."': $e",
            desc => $c->loc('Failed to delete device firmware'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
}

sub devfw_edit :Chained('devfw_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $c->stash->{devfw}->get_inflated_columns };
    $params->{device}{id} = delete $params->{device_id};
    $params = $params->merge($c->session->{created_objects});
    if($posted) {
        $c->req->params->{data} = $c->req->upload('data');
    }
    $form = NGCP::Panel::Form::Device::Firmware->new;

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'device.create' => $c->uri_for('/device/model/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->values->{device_id} = $form->values->{device}{id};
                delete $form->values->{device};
                my $file = delete $form->values->{data};
                $form->values->{filename} = $file->filename;
                $form->values->{data} = $file->slurp;

                $c->stash->{devfw}->update($form->values);
                delete $c->session->{created_objects}->{device};
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated device firmware'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to update device firmware'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devfw_edit_flag => 1,
        form => $form,
    );
}

sub devfw_download :Chained('devfw_base') :PathPart('download') :Args(0) {
    my ($self, $c) = @_;

    my $fw = $c->stash->{devfw};

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $fw->filename . '"');
    $c->response->content_type('application/octet-stream');
    $c->response->body($fw->data);
}

sub devconf_ajax :Chained('base') :PathPart('config/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{devconf_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{devconf_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub devconf_create :Chained('base') :PathPart('config/create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Device::Config->new;

    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'device.create' => $c->uri_for('/device/model/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $devmod = $c->stash->{devmod_rs}->find($form->values->{device}{id},{'+columns' => [qw/mac_image front_image/]});
                my $devconf = $devmod->create_related('autoprov_configs', $form->values);
                delete $c->session->{created_objects}->{device};
                $c->session->{created_objects}->{config} = { id => $devconf->id };
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully created device configuration'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to create device configuration'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devconf_create_flag => 1,
        form => $form,
    );
}

sub devconf_base :Chained('base') :PathPart('config') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c, $devconf_id) = @_;

    unless($devconf_id->is_int) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid device config id '$devconf_id'",
            desc => $c->loc('Invalid device configuration id'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devconf} = $c->stash->{devconf_rs}->find($devconf_id,{'+columns' => 'data'});
    unless($c->stash->{devconf}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "device configuration with id '$devconf_id' not found",
            desc => $c->loc('Device configuration not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
}

sub devconf_delete :Chained('devconf_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devconf}->delete;
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{devconf}->get_inflated_columns },
            desc => $c->loc('Device configuration successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete device configuration with id '".$c->stash->{devconf}->id."': $e",
            desc => $c->loc('Failed to delete device configuration'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
}

sub devconf_edit :Chained('devconf_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $c->stash->{devconf}->get_inflated_columns };
    $params->{device}{id} = delete $params->{device_id};
    $params = $params->merge($c->session->{created_objects});
    $form = NGCP::Panel::Form::Device::Config->new;

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'device.create' => $c->uri_for('/device/model/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->values->{device_id} = $form->values->{device}{id};
                delete $form->values->{device};

                use Data::Printer; p $form->values;
                $c->stash->{devconf}->update($form->values);
                delete $c->session->{created_objects}->{device};
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully updated device configuration'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to update device configuration'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devconf_edit_flag => 1,
        form => $form,
    );
}

sub devconf_download :Chained('devconf_base') :PathPart('download') :Args(0) {
    my ($self, $c) = @_;

    my $conf = $c->stash->{devconf};

    $c->response->content_type($conf->content_type);
    $c->response->body($conf->data);
}

sub devprof_ajax :Chained('base') :PathPart('profile/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{devprof_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{devprof_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub devprof_create :Chained('base') :PathPart('profile/create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Device::Profile->new;

    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'config.create' => $c->uri_for('/device/config/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->values->{config_id} = $form->values->{config}{id};
                delete $form->values->{config};

                $c->model('DB')->resultset('autoprov_profiles')->create($form->values);

                delete $c->session->{created_objects}->{config};
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Successfully created device profile'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to create device profile'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devprof_create_flag => 1,
        form => $form,
    );
}

sub devprof_base :Chained('base') :PathPart('profile') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c, $devprof_id) = @_;

    unless($devprof_id->is_int) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid device profile id '$devprof_id'",
            desc => $c->loc('Invalid device profile id'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devprof} = $c->stash->{devprof_rs}->find($devprof_id);
    unless($c->stash->{devprof}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "device profile with id '$devprof_id' not found",
            desc => $c->loc('Device profile not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
}

sub devprof_extensions :Chained('devprof_base') :PathPart('extensions') :Args(0):Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;


    my $rs = $c->stash->{devprof}->config->device->autoprov_extensions_link;
    my $device_info = { $c->stash->{devprof}->config->device->get_inflated_columns }; 
    foreach(qw/front_image mac_image/){
        delete $device_info->{$_};
    }

    my $data = {
        'device'  => $device_info,
        'profile' => { $c->stash->{devprof}->get_inflated_columns},
        'extensions' => { map {
            $_->extension->id => { 
                $_->extension->get_inflated_columns,
                'ranges' => [ 
                    map {
                        $_->get_inflated_columns,
                        'annotations' => [
                            map {{
                                $_->get_inflated_columns,
                            }} $_->annotations->all,
                        ],
                    } $_->extension->autoprov_device_line_ranges->all 
                ],
            }
        } $rs->all },
    };
    $c->stash(
        aaData               => $data,
        iTotalRecords        => 1,
        iTotalDisplayRecords => 1,
        sEcho                => int($c->request->params->{sEcho} // 1),
    );

    $c->detach( $c->view("JSON") );
}


sub devprof_extensions_form :Chained('devprof_base') :PathPart('extensions_field') :Args(0):Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;
    my $form = NGCP::Panel::Form::Customer::PbxFieldDeviceExtensions->new;
    $form->process(
        #posted => 0,
        params => $c->request->params,
        #item => $params
    );
    $c->stash->{form} = $form;
    $c->stash->{model_extensions_rs} = $c->model('DB')->resultset('autoprov_device_extensions')->search_rs({
            'device_id' => $c->stash->{devprof}->config->device_id,
        }
    );
    $c->stash->{template} = 'device/extensions_field.tt';
    $c->detach($c->view('TT'));
}

sub devprof_get_lines :Chained('devprof_base') :PathPart('lines/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{devprof}->config->device->autoprov_device_line_ranges;
    my $cols = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('ID') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'num_lines', search => 1, title => $c->loc('Number of Lines/Keys') },
        { name => 'can_private', search => 1, title => $c->loc('Private Line') },
        { name => 'can_shared', search => 1, title => $c->loc('Shared Line') },
        { name => 'can_blf', search => 1, title => $c->loc('BLF Key') },
    ]);
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $cols);
    $c->detach( $c->view("JSON") );
}

sub devprof_get_annotated_lines :Chained('devprof_base') :PathPart('annolines/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;
    $self->get_annotated_lines($c, $c->stash->{devprof}->config->device->autoprov_device_line_ranges );
}

sub devmod_get_annotated_lines :Chained('devmod_base') :PathPart('annolines/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;
    $self->get_annotated_lines($c, $c->stash->{devmod}->autoprov_device_line_ranges );
}

sub get_annotated_lines :Privat {
    my ($self, $c, $rs) = @_;

    my @ranges = map {{
        $_->get_inflated_columns,
        annotations => [
            map {{
                $_->get_inflated_columns,
            }} $_->annotations->all,
        ],
    }} $rs->all;

    $c->stash(aaData               => \@ranges,
              iTotalRecords        => scalar @ranges,
              iTotalDisplayRecords => scalar @ranges,
              sEcho                => int($c->request->params->{sEcho} // 1),
    );

    $c->detach( $c->view("JSON") );
}
sub devprof_delete :Chained('devprof_base') :PathPart('delete') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devprof}->delete;
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{devprof}->get_inflated_columns },
            desc => $c->loc('Device profile successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete device profile with id '".$c->stash->{devprof}->id."': $e",
            desc => $c->loc('Failed to delete device profile'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
}

sub devprof_edit :Chained('devprof_base') :PathPart('edit') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $c->stash->{devprof}->get_inflated_columns };
    $params->{config}{id} = delete $params->{config_id};
    $params = $params->merge($c->session->{created_objects});
    $form = NGCP::Panel::Form::Device::Profile->new;

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'config.create' => $c->uri_for('/device/config/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->values->{config_id} = $form->values->{config}{id};
                delete $form->values->{config};

                $c->stash->{devprof}->update($form->values);

                delete $c->session->{created_objects}->{config};
            });
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                data => { $c->stash->{devprof}->get_inflated_columns },
                desc => $c->loc('Successfully updated device profile'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to update device profile'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devprof_edit_flag => 1,
        form => $form,
    );
}

sub dev_field_ajax :Chained('base') :PathPart('device/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{fielddev_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{fielddev_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub dev_field_config :Chained('/') :PathPart('device/autoprov/config') :Args() {
    my ($self, $c, $id) = @_;

    # this is going to be used if we want to do the cert check on the server,
    # the format is like this:
    # /C=US/ST=708105B37234/L=CBT153908BX/O=Cisco Systems, Inc./OU=cisco.com/CN=SPA-525G2, MAC: 708105B37234, Serial: CBT153908BX/emailAddress=linksys-certadmin@cisco.com
    # however, we should do it on nginx, but we need a proper CA cert
    # from cisco for checking the client cert?
    $c->log->debug("SSL_CLIENT_M_DN: " . ($c->request->env->{SSL_CLIENT_M_DN} // ""));
    unless(
        ($c->user_exists && ($c->user->roles eq "admin" || $c->user->roles eq "reseller")) ||
        defined $c->request->env->{SSL_CLIENT_M_DN}
    ) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("403 - unauthenticated config access");
        } else {
            $c->response->body("403 - forbidden");
        }
        $c->response->status(403);
        return;
    }

    unless($id) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - device id not given");
        } else {
            $c->response->body("404 - device not found");
        }
        $c->response->status(404);
        return;
    }
    if($id =~ /^([0-9a-f]{12})\-directory\.xml$/) {
        $c->log->debug("identified bootstrap path part '$id' as polycom directory request");
        $c->res->redirect($c->uri_for_action("/pbx/polycom_directory_list", $id));
        return;
    }

    $id =~ s/\.cfg$//;

    $id =~ s/^([^\=]+)\=0$/$1/;
    $id = lc $id;
    $id =~ s/\-[a-z]+$//;

=pod
    my $yealink_key;
    if($id =~ s/_secure\.enc$//) {
        # mark to serve master-encrypted device key instead of config
        $yealink_key = $c->config->{autoprovisioning}->{yealink_key};
    }
=cut    

    # print access details for external rate limiting (e.g. fail2ban)
    my $ip;
    if(defined $c->req->headers->header('X-Forwarded-For')) {
        $ip = (split(/\s*,\s*/, $c->req->headers->header('X-Forwarded-For')))[0];
    } else {
        $ip = $c->req->address;
    }

    my $dev = $c->model('DB')->resultset('autoprov_field_devices')->find({
        identifier => $id
    });
    unless($dev) {
        $c->log->warn("Unknown autoprov config '$id' for '$ip'");
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - device id '" . $id . "' not found");
        } else {
            $c->response->body("404 - device not found");
        }
        $c->response->status(404);
        return;
    }
    $c->log->info("Serving autoprov config for '$id' to '$ip'");

=pod
    if(defined $yealink_key && defined $dev->encryption_key) {
        my $cipher = Crypt::Rijndael->new(
            $yealink_key, Crypt::Rijndael::MODE_ECB()
        );
        $c->response->content_type('text/plain');
        $c->response->body($cipher->encrypt($dev->encryption_key));
        $c->response->status(200);
        return;
    }
=cut

    my $model = $dev->profile->config->device;

    # TODO: only if not set in model config!
    my $schema = $c->config->{deviceprovisioning}->{secure} ? 'https' : 'http';
    my $host = $c->config->{deviceprovisioning}->{host} // $c->req->uri->host;
    my $port = $c->config->{deviceprovisioning}->{port} // 1444;

    my $vars = {
        config => {
            url => "$schema://$host:$port/device/autoprov/config/$id",
            baseurl => "$schema://$host:$port/device/autoprov/config/",
            mac => $id,
        },
        firmware => {
        },
        phone => {
            stationname => $dev->station_name,
            lineranges => [],
        },
        directory => {
            spaurl => "$schema://$host:$port/pbx/directory/spa/$id",
            panaurl => "$schema://$host:$port/pbx/directory/panasonic",
            yeaurl => "$schema://$host:$port/pbx/directory/yealink?userid=$id",
            name => 'PBX Address Book',
        }
    };

    $vars->{firmware}->{baseurl} = "$schema://$host:$port/device/autoprov/firmware";
    my $latest_fw = $c->model('DB')->resultset('autoprov_firmwares')->search({
        device_id => $model->id,
    }, {
        order_by => { -desc => 'version' },
    })->first;
    if($latest_fw) {
        $vars->{firmware}->{maxversion} = $latest_fw->version;
    }

    my @lines = ();
    foreach my $linerange($model->autoprov_device_line_ranges->all) {
        my $range = {
            name => $linerange->name,
            num_lines => $linerange->num_lines,
            lines => [],
        };
        foreach my $line($linerange->autoprov_field_device_lines->search({ device_id => $dev->id })->all) {
            my $sub = $line->provisioning_voip_subscriber;
            my $display_name = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c,
                prov_subscriber => $sub,
                attribute => 'display_name',
            );
            if($display_name->first) {
                $display_name = $display_name->first->value;
            } else {
                $display_name = $sub->username;
            };
            my $t38 = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c,
                prov_subscriber => $sub,
                attribute => 'enable_t38',
            );
            if($t38->first) {
                $t38 = $t38->first->value;
            } else {
                $t38 = 0;
            };
            # TODO: only push password for private/shared line?
            my $aliases = [ $sub->voip_dbaliases->search({ is_primary => 0 })->get_column("username")->all ];
            my $primary = $sub->voip_dbaliases->search({ is_primary => 1 })->get_column("username")->first;

            push @{ $range->{lines} }, {
                alias_numbers => $aliases,
                primary_number => $primary,
                extension => $sub->pbx_extension,
                username => $sub->username,
                domain => $sub->domain->domain,
                password => $sub->password,
                displayname => $display_name,
                keynum => $line->key_num,
                type => $line->line_type,
                t38 => $t38,
            };
        }
        push @{ $vars->{phone}->{lineranges} }, $range;
    }

    my $data = $dev->profile->config->data;
    my $processed_data = "";
    my $t = Template->new;
    $t->process(\$data, $vars, \$processed_data) || do {
        my $error = $t->error();
        my $msg = "error processing template, type=".$error->type.", info='".$error->info."'";
        $c->log->error($msg);
        $c->response->body("500 - error creating template:\n$msg");
        $c->response->status(500);
        return;
    };

    $c->log->debug("providing config to $id");
    $c->log->debug($processed_data);

=pod
    if(defined $dev->encryption_key) {
        # yealink uses weak ECB mode, but well...
        my $cipher = Crypt::Rijndael->new(
            $dev->encryption_key, Crypt::Rijndael::MODE_ECB()
        );
        $c->response->content_type("application/octet-stream");
        $c->response->body($cipher->encrypt($processed_data));
    } else {
=cut    
        $c->response->content_type($dev->profile->config->content_type);
        $c->response->body($processed_data);
=pod
    }
=cut
}

sub dev_field_bootstrap :Chained('/') :PathPart('device/autoprov/bootstrap') :Args() {
    my ($self, $c, @id) = @_;
    my $id;
    foreach my $did (@id) {
        $c->log->debug("checking bootstrap path part '$did'");
        $did =~ s/\.cfg$//;
        $did =~ s/^([^\=]+)\=0$/$1/;
        $did = lc $did;
        $did =~ s/\-[a-z]+$//;
        if($did =~ /^[0-9a-f]{12}$/) {
            $c->log->debug("identified bootstrap path part '$did' as valid device id");
            $id = $did;
            last;
        }
    }
    unless($id) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - device id not given");
        } else {
            $c->response->body("404 - device not found");
        }
        $c->response->status(404);
        return;
    }

    my $ip;
    if(defined $c->req->headers->header('X-Forwarded-For')) {
        $ip = (split(/\s*,\s*/, $c->req->headers->header('X-Forwarded-For')))[0];
    } else {
        $ip = $c->req->address;
    }

    my $dev = $c->model('DB')->resultset('autoprov_field_devices')->find({
        identifier => $id
    });
    unless($dev) {
        $c->log->warn("Unknown autoprov bootstrap config '$id' for '$ip'");
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - device id '" . $id . "' not found");
        } else {
            $c->response->body("404 - device not found");
        }
        $c->response->status(404);
        return;
    }
    $c->log->info("Serving autoprov bootstrap config for '$id' to '$ip'");

    my $model = $dev->profile->config->device;

    # TODO: only if not set in model config!
    my $schema = $c->config->{deviceprovisioning}->{secure} ? 'https' : 'http';
    my $host = $c->config->{deviceprovisioning}->{host} // $c->req->uri->host;
    my $port = $c->config->{deviceprovisioning}->{port} // 1444;
    my $boot_port = $c->config->{deviceprovisioning}->{bootstrap_port} // 1445;

    my $vars = {
        config => {
            url => "$schema://$host:$port/device/autoprov/config/$id",
            baseurl => "$schema://$host:$port/device/autoprov/config/",
            caurl => "http://$host:$boot_port/device/autoprov/cacert",
            ca => $c->model('CA')->get_provisioning_root_ca_cert($c),
            mac => $id,
            bootstrap => 1,
        },
        firmware => {
            # we return the current (bootstrap) host here to allow the
            # device to upgrade the firmware
            baseurl => "http://" . $c->req->uri->host . ":" .
                         $c->req->uri->port . "/device/autoprov/firmware",
        },
    };

    my $latest_fw = $c->model('DB')->resultset('autoprov_firmwares')->search({
        device_id => $model->id,
    }, {
        order_by => { -desc => 'version' },
    })->first;
    if($latest_fw) {
        $vars->{firmware}->{maxversion} = $latest_fw->version;
    }

    my $data = $dev->profile->config->data;
    my $processed_data = "";
    my $t = Template->new;
    $t->process(\$data, $vars, \$processed_data) || do {
        my $error = $t->error();
        my $msg = "error processing template, type=".$error->type.", info='".$error->info."'";
        $c->log->error($msg);
        $c->response->body("500 - error creating template:\n$msg");
        $c->response->status(500);
        return;
    };

    $c->log->debug("providing config to $id");
    $c->log->debug($processed_data);

    $c->response->content_type($dev->profile->config->content_type);
    $c->response->body($processed_data);
}

sub dev_servercert :Chained('/') :PathPart('device/autoprov/servercert') :Args(0) {
    my ($self, $c) = @_;
    my $cert = $c->model('CA')->get_provisioning_server_cert($c);
    $c->res->headers(HTTP::Headers->new(
        'Content-Type' => 'application/octet-stream',
        #'Content-Disposition' => sprintf('attachment; filename=%s', "provisioning-certificate.pem")
    ));
    $c->res->body($cert);
    return;
}

sub dev_cacert :Chained('/') :PathPart('device/autoprov/cacert') :Args(0) {
    my ($self, $c) = @_;
    my $cert = $c->model('CA')->get_provisioning_ca_cert($c);
    $c->res->headers(HTTP::Headers->new(
        'Content-Type' => 'application/octet-stream',
        #'Content-Disposition' => sprintf('attachment; filename=%s', "provisioning-certificate.pem")
    ));
    $c->res->body($cert);
    return;
}

sub dev_static_jitsi_config :Chained('/') :PathPart('device/autoprov/static/jitsi') :Args(0) {
    my ($self, $c) = @_;

    unless($c->req->params->{user} && $c->req->params->{pass} && $c->req->params->{uuid}) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - user/pass/uuid triple not specified in params");
        } else {
            $c->response->body("404 - missing config parameters");
        }
        $c->response->status(404);
        return;
    }
    my $uri = $c->req->params->{user};
    my $pass = $c->req->params->{pass};
    my $uuid = $c->req->params->{uuid};
    my ($user, $domain, $tmp) = split /\@/, $uri;
    if(defined $tmp) {
        $user = $user . '@' . $domain;
        $domain = $tmp;
    }
    unless($user && $domain) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - user param not in format user\@domain");
        } else {
            $c->response->body("404 - invalid user config parameters");
        }
        $c->response->status(404);
        return;
    }

    if($c->config->{deviceprovisioning}->{softphone_webauth}) {
        my $sub = $c->model('DB')->resultset('provisioning_voip_subscribers')->find({
           webusername => $user,
           'domain.domain' => $domain,
           webpassword => $pass,
        },{
            join => 'domain',
        });
        unless($sub) {
            if($c->config->{features}->{debug}) {
                $c->response->body("404 - webuser authentication failed");
            } else {
                $c->response->body("404 - invalid user config parameters");
            }
            $c->response->status(404);
            return;
        }
        $user = $sub->username;
        $pass = $sub->password;
    }

    my $sipacc = 'accsipngcp'.$user.$domain;
    my $xmppacc = 'accxmppngcp'.$user.$domain;
    $sipacc =~ s/[^a-zA-Z0-9]//g;
    $xmppacc =~ s/[^a-zA-Z0-9]//g;
    my $provserver = 'https\://' . $c->req->uri->host . '\:' . $c->req->uri->port .
            '/device/autoprov/static/jitsi';
    my $server_ip;
    if(defined $c->config->{sip}->{lb}) {
        if(ref $c->config->{sip}->{lb} eq 'ARRAY') {
            # if we have more lbs, pick a random one
            $server_ip = $c->config->{sip}->{lb}->[rand @{ $c->config->{sip}->{lb} }];
        } else {
            $server_ip = $c->config->{sip}->{lb};
        }
    } else {
        $server_ip = $c->req->uri->host;
    }
    my $server_port;
    my $server_proto;

    $server_port = $c->config->{sip}->{tls_port} // 5060;
    $server_proto = $c->config->{sip}->{tls_port} ? 'TLS' : 'UDP';
    $c->log->info("jitsiprov gathered required information, sipacc=$sipacc, xmppacc=$xmppacc");

    my $config = <<"EOF";
net.java.sip.communicator.plugin.provisioning.METHOD=Manual
net.java.sip.communicator.plugin.provisioning.URL=$provserver?user\\=\${username}&pass\\=\${password}&uuid\\=\${uuid}
net.java.sip.communicator.impl.protocol.sip.$sipacc=$sipacc
net.java.sip.communicator.impl.protocol.sip.$sipacc.ACCOUNT_UID=SIP\\:$user\@$domain
net.java.sip.communicator.impl.protocol.sip.$sipacc.DEFAULT_ENCRYPTION=true
net.java.sip.communicator.impl.protocol.sip.$sipacc.DEFAULT_SIPZRTP_ATTRIBUTE=true
net.java.sip.communicator.impl.protocol.sip.$sipacc.DTMF_METHOD=AUTO_DTMF
net.java.sip.communicator.impl.protocol.sip.$sipacc.DTMF_MINIMAL_TONE_DURATION=70
net.java.sip.communicator.impl.protocol.sip.$sipacc.PASSWORD=$pass
net.java.sip.communicator.impl.protocol.sip.$sipacc.ENCRYPTION_PROTOCOL.ENCRYPTION_PROTOCOL.ZRTP=0
net.java.sip.communicator.impl.protocol.sip.$sipacc.ENCRYPTION_PROTOCOL_STATUS.ENCRYPTION_PROTOCOL_STATUS.ZRTP=true
net.java.sip.communicator.impl.protocol.sip.$sipacc.FORCE_P2P_MODE=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.VOICEMAIL_CHECK_URI=sip\\:voicebox\@$domain
net.java.sip.communicator.impl.protocol.sip.$sipacc.VOICEMAIL_URI=
net.java.sip.communicator.impl.protocol.sip.$sipacc.IS_PRESENCE_ENABLED=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.KEEP_ALIVE_INTERVAL=25
net.java.sip.communicator.impl.protocol.sip.$sipacc.KEEP_ALIVE_METHOD=OPTIONS
net.java.sip.communicator.impl.protocol.sip.$sipacc.OVERRIDE_ENCODINGS=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.POLLING_PERIOD=30
net.java.sip.communicator.impl.protocol.sip.$sipacc.PROTOCOL_NAME=SIP
net.java.sip.communicator.impl.protocol.sip.$sipacc.SAVP_OPTION=0
net.java.sip.communicator.impl.protocol.sip.$sipacc.SERVER_ADDRESS=$domain
net.java.sip.communicator.impl.protocol.sip.$sipacc.PROXY_AUTO_CONFIG=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.PROXY_ADDRESS=$server_ip
net.java.sip.communicator.impl.protocol.sip.$sipacc.PROXY_PORT=$server_port
net.java.sip.communicator.impl.protocol.sip.$sipacc.PREFERRED_TRANSPORT=$server_proto
net.java.sip.communicator.impl.protocol.sip.$sipacc.SUBSCRIPTION_EXPIRATION=3600
net.java.sip.communicator.impl.protocol.sip.$sipacc.USER_ID=$user\@$domain
net.java.sip.communicator.impl.protocol.sip.$sipacc.XCAP_ENABLE=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.XIVO_ENABLE=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.cusax.XMPP_ACCOUNT_ID=$xmppacc
net.java.sip.communicator.impl.protocol.jabber.$xmppacc=$xmppacc
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ACCOUNT_UID=Jabber\\:$user\@$domain\@$domain
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ALLOW_NON_SECURE=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.AUTO_DISCOVER_JINGLE_NODES=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.AUTO_DISCOVER_STUN=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.AUTO_GENERATE_RESOURCE=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.BYPASS_GTALK_CAPABILITIES=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.CALLING_DISABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.DEFAULT_ENCRYPTION=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.DEFAULT_SIPZRTP_ATTRIBUTE=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.DTMF_METHOD=AUTO_DTMF
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.DTMF_MINIMAL_TONE_DURATION=70
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.PASSWORD=$pass
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ENCRYPTION_PROTOCOL.SDES=1
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ENCRYPTION_PROTOCOL.ZRTP=0
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ENCRYPTION_PROTOCOL_STATUS.SDES=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ENCRYPTION_PROTOCOL_STATUS.ZRTP=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.GMAIL_NOTIFICATIONS_ENABLED=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.GOOGLE_CONTACTS_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.GTALK_ICE_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ICE_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.IS_PREFERRED_PROTOCOL=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.IS_SERVER_OVERRIDDEN=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.JINGLE_NODES_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.OVERRIDE_ENCODINGS=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.OVERRIDE_PHONE_SUFFIX=
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.PROTOCOL_NAME=Jabber
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.RESOURCE=sipwise
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.RESOURCE_PRIORITY=30
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.SDES_CIPHER_SUITES=AES_CM_128_HMAC_SHA1_80,AES_CM_128_HMAC_SHA1_32
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.SERVER_ADDRESS=$domain
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.SERVER_PORT=5222
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.TELEPHONY_BYPASS_GTALK_CAPS=
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.UPNP_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.USER_ID=$user\@$domain
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.USE_DEFAULT_STUN_SERVER=true
EOF

    if($c->config->{deviceprovisioning}->{softphone_lockdown}) {
        $config .= <<"EOF";
net.java.sip.communicator.impl.protocol.sip.$sipacc.IS_STATUS_MENU_HIDDEN=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.IS_STATUS_MENU_HIDDEN=true
net.java.sip.communicator.impl.gui.main.menus.AUTO_ANSWER_MENU_DISABLED=true
net.java.sip.communicator.impl.gui.main.configforms.SHOW_ACCOUNT_CONFIG=false
net.java.sip.communicator.plugin.generalconfig.DISABLED=true
net.java.sip.communicator.impl.neomedia.AUDIO_CONFIG_DISABLED=true
net.java.sip.communicator.impl.neomedia.VIDEO_CONFIG_DISABLED=true
net.java.sip.communicator.impl.neomedia.devicesconfig.DISABLED=true
net.java.sip.communicator.impl.neomedia.encodingsconfig.DISABLED=true
net.java.sip.communicator.impl.neomedia.videomoresettingsconfig.DISABLED=true
net.java.sip.communicator.plugin.securityconfig.DISABLED=true
net.java.sip.communicator.impl.neomedia.zrtpconfig.DISABLED=true
net.java.sip.communicator.plugin.securityconfig.masterpasswordconfig.DISABLED=true
net.java.sip.communicator.plugin.advancedconfig.DISABLED=true
net.java.sip.communicator.plugin.generalconfig.sipconfig.DISABLED=true
net.java.sip.communicator.impl.neomedia.callrecordingconfig.DISABLED=true
net.java.sip.communicator.impl.neomedia.h264config.DISABLED=true
EOF
    }

    $c->response->content_type('text/plain');
    $c->response->body($config);
}

sub dev_field_firmware_base :Chained('/') :PathPart('device/autoprov/firmware') :CaptureArgs(1) {
    my ($self, $c, $id) = @_;

    unless($id) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - device id not given");
        } else {
            $c->response->body("404 - device not found");
        }
        $c->response->status(404);
        return;
    }
    $id =~ s/^([^\=]+)\=0$/$1/;
    $id = lc $id;

    my $dev = $c->model('DB')->resultset('autoprov_field_devices')->find({
        identifier => $id
    });
    unless($dev) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - device id '" . $id . "' not found");
        } else {
            $c->response->body("404 - device not found");
        }
        $c->response->status(404);
        return;
    }

    $c->stash->{dev} = $dev;
}

sub dev_field_firmware_download :Chained('dev_field_firmware_base') :PathPart('version') :Args(1) {
    my ($self, $c, $ver) = @_;

    my $rs = $c->stash->{dev}->profile->config->device->autoprov_firmwares->search({
        device_id => $c->stash->{dev}->profile->config->device->id,
        version => { '=' => $ver },
    });

    my $fw = $rs->first;
    unless($fw) {
        $c->response->content_type('text/plain');
        $c->response->body("404 - firmware version '$ver' not found latest");
        $c->response->status(404);
        return;
    }

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $fw->filename . '"');
    $c->response->content_type('application/octet-stream');
    $c->response->body($fw->data);
}

sub dev_field_firmware_version_base :Chained('dev_field_firmware_base') :PathPart('from') :CaptureArgs(1) {
    my ($self, $c, $fwver) = @_;

    unless(defined $fwver) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - firmware name not given");
        } else {
            $c->response->body("404 - firmware not found");
        }
        $c->response->status(404);
        return;
    }

    $c->stash->{dev_fw_string} = $fwver;
    my $dev = $c->stash->{dev};
    $c->stash->{fw_rs} = $dev->profile->config->device->autoprov_firmwares;
}

sub dev_field_firmware_next :Chained('dev_field_firmware_version_base') :PathPart('next') :Args(0) {
    my ($self, $c) = @_;

    my $rs = $c->stash->{fw_rs}->search({
        device_id => $c->stash->{dev}->profile->config->device->id,
        version => { '>' => $c->stash->{dev_fw_string} },
    }, {
        order_by => { -asc => 'version' },
    });

    my $fw = $rs->first;
    unless($fw) {
        $c->response->content_type('text/plain');
        $c->response->body("404 - current firmware version '" . $c->stash->{dev_fw_string} . "' is latest");
        $c->response->status(404);
        return;
    }

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $fw->filename . '"');
    $c->response->content_type('application/octet-stream');
    $c->response->body($fw->data);
}

sub dev_field_firmware_latest :Chained('dev_field_firmware_version_base') :PathPart('latest') :Args(0) {
    my ($self, $c) = @_;

    my $rs = $c->stash->{fw_rs}->search({
        device_id => $c->stash->{dev}->profile->config->device->id,
        version => { '>' => $c->stash->{dev_fw_string} },
    }, {
        order_by => { -desc => 'version' },
    });

    my $fw = $rs->first;
    unless($fw) {
        $c->response->content_type('text/plain');
        $c->response->body("404 - current firmware version '" . $c->stash->{dev_fw_string} . "' is latest");
        $c->response->status(404);
        return;
    }

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $fw->filename . '"');
    $c->response->content_type('application/octet-stream');
    $c->response->body($fw->data);
}


__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
