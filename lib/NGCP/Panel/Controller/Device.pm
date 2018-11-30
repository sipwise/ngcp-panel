package NGCP::Panel::Controller::Device;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use Template;
use Crypt::Rijndael;
use Digest::MD5 qw/md5_hex/;
use Storable qw/freeze/;
use JSON qw(decode_json encode_json);
use NGCP::Panel::Form;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DeviceBootstrap;
use NGCP::Panel::Utils::Device;
use NGCP::Panel::Utils::DeviceFirmware;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Preferences;
use DateTime::Format::HTTP;

use parent 'Catalyst::Controller';

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
            'columns' => [qw/id reseller_id type vendor model front_image_type mac_image_type num_lines bootstrap_method bootstrap_uri extensions_num/,
                {
                    mac_image_exists   => \'mac_image is not null',
                    front_image_exists => \'front_image is not null',
                }
            ],
    });

    $reseller_id and $devmod_rs = $devmod_rs->search({ reseller_id => $reseller_id });
    $c->stash->{devmod_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'type', search => 1, title => $c->loc('Type') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'vendor', search => 1, title => $c->loc('Vendor') },
        { name => 'model', search => 1, title => $c->loc('Model') },
    ]);

    my $devfw_rs = $c->model('DB')->resultset('autoprov_firmwares')->search_rs(undef,{'columns' => [qw/id device_id version filename tag/],
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
        { name => 'tag', search => 1, title => $c->loc('Firmware Tag') },
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
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{devmod_dt_columns},
        sub {
            my ($result) = @_;
            my %data = (
                mac_image_exists => $result->get_column('mac_image_exists'),
                front_image_exists => $result->get_column('front_image_exists'),
            );
            return %data
        },
    );
    $c->detach( $c->view("JSON") );
}

sub extensionmodel_ajax :Chained('base') :PathPart('extensionmodel/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{devmod_rs}->search_rs({
        'me.type' => 'extension',
    });
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{devmod_dt_columns},
        sub {
            my ($result) = @_;
            my %data = (
                mac_image_exists => $result->get_column('mac_image_exists'),
                front_image_exists => $result->get_column('front_image_exists'),
            );
            return %data
        },
    );
    $c->detach( $c->view("JSON") );
}

sub devmod_create :Chained('base') :PathPart('model/create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::ModelAdmin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Model", $c);
    }

    my $params = {};
    $params = merge($params, $c->session->{created_objects});
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

                #preparation of the connectable_models before store_and_process_device_model call
                if(defined $form->values->{connectable_models}){
                    $form->values->{connectable_models} = decode_json($form->values->{connectable_models});
                }
                my $devmod = NGCP::Panel::Utils::Device::store_and_process_device_model($c, undef, $form->values);

                delete $c->session->{created_objects}->{reseller};
                $c->session->{created_objects}->{device} = { id => $devmod->id };
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully created device model'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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

sub prepare_connectable :Private{
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

    unless(is_int($devmod_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "invalid device model id '$devmod_id'",
            desc => $c->loc('Invalid device model id'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
    my $devmod = $c->stash->{devmod_rs}->find($devmod_id,{'+columns' => [qw/mac_image front_image/]});
    unless($devmod) {
        NGCP::Panel::Utils::Message::error(
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
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { id => $c->stash->{devmod}->id,
                      model => $c->stash->{devmod}->model,
                      vendor => $c->stash->{devmod}->vendor },
            desc => $c->loc('Device model successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
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
    $params = merge($params, $c->session->{created_objects});
    $c->stash(edit_model => 1); # to make front_image optional
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::ModelAdmin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Model", $c);
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

                #preparation of the connectable_models before store_and_process_device_model call
                if(defined $form->values->{connectable_models}){
                    $form->values->{connectable_models} = decode_json($form->values->{connectable_models});
                }
                NGCP::Panel::Utils::Device::store_and_process_device_model($c, $c->stash->{devmod}, $form->values);

                delete $c->session->{created_objects}->{reseller};
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                data => { id => $c->stash->{devmod}->id,
                          model => $c->stash->{devmod}->model,
                          vendor => $c->stash->{devmod}->vendor },
                desc => $c->loc('Successfully updated device model'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Firmware", $c);

    my $params = {};
    $params = merge($params, $c->session->{created_objects});
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
                my $devmod = $c->stash->{devmod_rs}->find($form->values->{device}{id},{'+columns' => [qw/mac_image front_image/]});
                my $devfw = $devmod->create_related('autoprov_firmwares', $form->values);
                if ($file->size) {
                    NGCP::Panel::Utils::DeviceFirmware::insert_firmware_data(
                        c => $c, fw_id => $devfw->id, data_fh => $file->fh
                    );
                }
                delete $c->session->{created_objects}->{device};
                $c->session->{created_objects}->{firmware} = { id => $devfw->id };
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully created device firmware'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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

    unless(is_int($devfw_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "invalid device firmware id '$devfw_id'",
            desc => $c->loc('Invalid device firmware id'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devfw} = $c->stash->{devfw_rs}->find($devfw_id);
    unless($c->stash->{devfw}) {
        NGCP::Panel::Utils::Message::error(
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
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{devfw}->get_inflated_columns },
            desc => $c->loc('Device firmware successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
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
    $params = merge($params, $c->session->{created_objects});
    if($posted) {
        $c->req->params->{data} = $c->req->upload('data');
    }
    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Firmware", $c);

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
                $c->stash->{devfw}->update($form->values);
                if ($file->size) {
                    NGCP::Panel::Utils::DeviceFirmware::insert_firmware_data(
                        c => $c,
                        fw_id => $c->stash->{devfw}->id,
                        data_fh => $file->fh
                    );
                }
                delete $c->session->{created_objects}->{device};
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated device firmware'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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
    $c->response->body(
        NGCP::Panel::Utils::DeviceFirmware::get_firmware_data(
            c => $c,
            fw_id => $fw->id
    ));
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
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Config", $c);

    my $params = {};
    $params = merge($params, $c->session->{created_objects});
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
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully created device configuration'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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

    unless(is_int($devconf_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "invalid device config id '$devconf_id'",
            desc => $c->loc('Invalid device configuration id'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devconf} = $c->stash->{devconf_rs}->find($devconf_id,{'+columns' => 'data'});
    unless($c->stash->{devconf}) {
        NGCP::Panel::Utils::Message::error(
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
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{devconf}->get_inflated_columns },
            desc => $c->loc('Device configuration successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
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
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Config", $c);

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
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated device configuration'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Profile", $c);

    my $params = {};
    $params = merge($params, $c->session->{created_objects});
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
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully created device profile'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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

    unless(is_int($devprof_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "invalid device profile id '$devprof_id'",
            desc => $c->loc('Invalid device profile id'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devprof} = $c->stash->{devprof_rs}->find($devprof_id);
    unless($c->stash->{devprof}) {
        NGCP::Panel::Utils::Message::error(
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
        iTotalRecordCountClipped        => \0,
        iTotalDisplayRecordCountClipped => \0,
        sEcho                => int($c->request->params->{sEcho} // 1),
    );

    $c->detach( $c->view("JSON") );
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

sub devprof_get_annotated_info :Chained('devprof_base') :PathPart('annolines/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;
    $self->get_annotated_info($c, $c->stash->{devprof}->config->device );
}

sub devmod_get_annotated_info :Chained('devmod_base') :PathPart('annolines/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;
    $self->get_annotated_info($c, $c->stash->{devmod} );
}

sub get_annotated_info :Private {
    my ($self, $c, $devmod) = @_;

    my $device_info = { $devmod->get_inflated_columns };
    foreach(qw/front_image mac_image/){
        delete $device_info->{$_};
    }
    my $gather_ranges_info = sub {
        my $rs = shift;
        return [ map {
                {
                    $_->get_inflated_columns,
                    'annotations' => [
                        map {{
                            $_->get_inflated_columns,
                        }} $_->annotations->all,
                    ],
                }
            }$rs->all
        ];
    };
    my $data = {
        'device'  => $device_info,
        'ranges' => $gather_ranges_info->( $devmod->autoprov_device_line_ranges ),
        'extensions' => { map {
            $_->extension->id => {
                $_->extension->get_inflated_columns,
                'ranges' => $gather_ranges_info->( $_->extension->autoprov_device_line_ranges ),
            }
        } $devmod->autoprov_extensions_link->all },
    };

    $c->stash(
        aaData               => $data,
        iTotalRecords        => 1,
        iTotalDisplayRecords => 1,
        iTotalRecordCountClipped        => \0,
        iTotalDisplayRecordCountClipped => \0, 
        sEcho                => int($c->request->params->{sEcho} // 1),
    );

    $c->detach( $c->view("JSON") );
}
sub devprof_delete :Chained('devprof_base') :PathPart('delete') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devprof}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{devprof}->get_inflated_columns },
            desc => $c->loc('Device profile successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
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
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Profile", $c);

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
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                data => { $c->stash->{devprof}->get_inflated_columns },
                desc => $c->loc('Successfully updated device profile'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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
    my $opt = $c->req->params->{opt};

    delete $c->response->cookies->{ngcp_panel_session};
    $c->response->headers->remove_header('Connection');
    $c->response->headers->remove_header('X-Catalyst');
    $c->response->headers->push_header('Last-Modified' => DateTime::Format::HTTP->format_datetime());

    $c->log->debug("SSL_CLIENT_M_DN: " . ($c->request->env->{SSL_CLIENT_M_DN} // ""));
    unless(
        ($c->user_exists && ($c->user->roles eq "admin" || $c->user->roles eq "reseller")) ||
        defined $c->request->env->{SSL_CLIENT_M_DN}
    ) {
        $c->log->info("unauthenticated config access to id '$id' via ip " . $c->req->address);
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

    $id =~ s/\.(cfg|ini|xml)$//;
    $id =~ s/^config\.//;

    $id =~ s/^([^\=]+)\=0$/$1/;
    $id = lc $id;
    $id =~ s/\-[a-z]+$//;
    $id =~ s/\-//g;

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

    # example DN format is:
    # /C=US/ST=708105B37234/L=CBT153908BX/O=Cisco Systems, Inc./OU=cisco.com/CN=SPA-525G2, MAC: 708105B37234, Serial: CBT153908BX/emailAddress=linksys-certadmin@cisco.com
    # if check is enabled, lowercase both DN and given MAC, strip colons and dashes from both, and try to
    # find given MAC as substring in DN
    if ($c->config->{security}->{autoprov_ssl_mac_check}) {
        my $dn = $c->request->env->{SSL_CLIENT_M_DN} // '';
        $dn = lc($dn);
        $dn =~ s/[:\-]//g;
        if (index($dn, $id) == -1) {
            $c->log->info("unauthorized config access to id '$id' from dn '$dn' via ip '$ip'");
            $c->response->content_type('text/plain');
            if($c->config->{features}->{debug}) {
                $c->response->body("403 - unauthorized config access");
            } else {
                $c->response->body("403 - forbidden");
            }
            $c->response->status(403);
            return;
        }
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
    my $schema = 'https';
    my $host = $c->config->{deviceprovisioning}->{host} // $c->req->uri->host;
    my $port = $c->config->{deviceprovisioning}->{port} // 1444;
    my $boot_port = $c->config->{deviceprovisioning}->{bootstrap_port} // 1445;

    my $vars = {
        opt => $opt,
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
        },
        ldap => {
            tls => $c->config->{ldap}->{tls},
            ip => $c->config->{ldap}->{ip},
            port => $c->config->{ldap}->{port},
            dn => ',dc=hpbx,dc=sipwise,dc=com', # uid=xxx,o=contract-id added below
            password => '', # set below
            base => ',dc=hpbx,dc=sipwise,dc=com', # o=contract-id added below
            nameattr => 'displayName',
            phoneattr => 'telephoneNumber'
        }
    };

    $vars->{firmware}->{baseurl} = "$schema://$host:$port/device/autoprov/firmware";
    $vars->{firmware}->{booturl} = "http://$host:$boot_port/device/autoprov/firmware";
    my $latest_fw = $c->model('DB')->resultset('autoprov_firmwares')->search({
        device_id => $model->id,
    }, {
        order_by => { -desc => 'version' },
    })->first;
    if($latest_fw) {
        $vars->{firmware}->{maxversion} = $latest_fw->version;
    }

    my $ldap_attr_set = 0;
    my @lines = ();
    my @field_models = $c->model('DB')->resultset('autoprov_devices')->search_rs({
            'autoprov_field_device_lines.device_id' => $dev->id,
        },
        {
            'join' => {'autoprov_device_line_ranges' => 'autoprov_field_device_lines'},
            '+select' => [
                {'' => \['me.type = ?', [ {} => 'phone' ] ], '-as' => 'is_phone_model' },
            ],
            '+as' => ['is_phone_model'],

            'group_by' => 'me.id',
            'order_by' => { -desc => 'is_phone_model' },
        }
    )->all ;
    foreach my $linerange( map { $_->autoprov_device_line_ranges->all } @field_models ) {
        my $range = {
            name => $linerange->name,
            num_lines => $linerange->num_lines,
            lines => [],
        };
        foreach my $line($linerange->autoprov_field_device_lines->search({ device_id => $dev->id })->all) {
            my $sub = $line->provisioning_voip_subscriber;

            my %sub_preferences_vars = (
                display_name               => $sub->username,
                enable_t38                 => 0,
                concurrent_max             => 0,
                concurrent_max_per_account => 0,
                cc                         => '',
                ac                         => '',
            );
            my $pref_rs = NGCP::Panel::Utils::Preferences::get_preferences_rs(
                c => $c,
                id => $sub->id,
                type => 'usr',
                #attribute => [keys %sub_preferences_vars],
            );
            my $preferences = get_inflated_columns_all($pref_rs, 'hash' => 'attribute', 'column' => 'value' );
            foreach my $key (keys %sub_preferences_vars){
                if(exists $preferences->{$key}){
                    $sub_preferences_vars{$key} = $preferences->{$key};
                }
            }
            $sub_preferences_vars{displayname} = delete $sub_preferences_vars{display_name};
            # TODO: only push password for private/shared line?
            my $aliases = [ $sub->voip_dbaliases->search({ is_primary => 0 })->get_column("username")->all ];
            my $primary = $sub->voip_dbaliases->search({ is_primary => 1 })->get_column("username")->first;

            push @{ $range->{lines} }, {
                alias_numbers  => $aliases,
                primary_number => $primary,
                extension      => $sub->pbx_extension,
                username       => $sub->username,
                domain         => $sub->domain->domain,
                password       => $sub->password,
                keynum         => $line->key_num,
                type           => $line->line_type,
                preferences    => $preferences,
                %sub_preferences_vars,
            };
            if(!$ldap_attr_set && $linerange->name eq "Full Keys" && $line->line_type eq "private") {
                $vars->{ldap}->{dn} = "uid=".$sub->uuid . ",o=" . $sub->account_id . $vars->{ldap}->{dn};
                $vars->{ldap}->{base} = "o=" . $sub->account_id . $vars->{ldap}->{base};
                $vars->{ldap}->{password} = $sub->password;
                $ldap_attr_set = 1;
            }
        }
        push @{ $vars->{phone}->{lineranges} }, $range;
    }
    my $preferences_device;
    my $preferences_device_dynamic;
    my $preferences_id = {
        'fielddev' => $dev->id,
        'dev'      => $model->id,
        'devprof'  => $dev->profile->id,
    };
    foreach my $type (keys %$preferences_id) {
        my $pref_rs = NGCP::Panel::Utils::Preferences::get_preferences_rs(
            c => $c,
            id => $preferences_id->{$type},
            type => $type,
        );
        my $pref_rs_dynamic = $pref_rs->search_rs({
                    'attribute.dynamic' => 1,
                }, {
                '+select' => [\'replace(attribute.attribute,"__","")' ],
                '+as' => ['attribute_normalized'],
        });
        $preferences_device_dynamic->{$type} = get_inflated_columns_all($pref_rs_dynamic,
            'hash' => 'attribute_normalized',
            'column' => 'value'
        );
        my $pref_rs_static = $pref_rs->search_rs({
            'attribute.dynamic' => 0,
        });
        $preferences_device->{$type} = get_inflated_columns_all($pref_rs_static,
            'hash' => 'attribute',
            'column' => 'value'
        );
    }
    my %preferences_device = (
        'model'    => $preferences_device->{dev},
        'profile'  => $preferences_device->{devprof},
        'persistent'   => {
            'model'    => {%{$preferences_device->{dev}}},
            'profile'  => {%{$preferences_device->{devprof}}},
            'device'   => $preferences_device->{fielddev},
        },
        'dynamic'   => {
            'model'    => $preferences_device_dynamic->{dev},
            'profile'  => $preferences_device_dynamic->{devprof},
            'device'   => $preferences_device_dynamic->{fielddev},
        },
        'device' => {
            %{$preferences_device->{dev}},
            %{$preferences_device_dynamic->{dev}},
            %{$preferences_device->{devprof}},
            %{$preferences_device_dynamic->{devprof}},
            %{$preferences_device->{fielddev}},
            %{$preferences_device_dynamic->{fielddev}},
        }
    );
    $vars->{preferences} //= {};
    $vars->{preferences}->{device} = \%preferences_device;

    my $data = $dev->profile->config->data;

    my $var_hash = md5_hex(freeze $vars);
    my $cfg_hash = md5_hex($data);
    $vars->{checksum} = md5_hex($var_hash . $cfg_hash);

    my $processed_data = "";
    my $t = Template->new({
        PLUGIN_BASE => 'NGCP::Panel::Template::Plugin',
    });
    $t->process(\$data, $vars, \$processed_data) || do {
        my $error = $t->error();
        my $msg = "error processing template, type=".$error->type.", info='".$error->info."'";
        $c->log->error($msg);
        $c->response->body("500 - error creating template:\n$msg");
        $c->response->status(500);
        return;
    };
    if($model->vendor eq "Audiocodes") {
        $processed_data .= "\r\n\r\n";
    }

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
    my $result = $self->dev_field_encrypt( $c, $dev, $processed_data, $vars);
    $c->response->content_type($result->{content_type});
    $c->response->body(${$result->{content}});
}

sub dev_field_encrypt :Private{
    my ($self, $c, $dev, $processed_data, $vars) = @_;

    my $result = {'content' => \$processed_data };

    my $model = $dev->profile->config->device;

    my $module = 'NGCP::Panel::Utils::Device';
    my $method = $module->can(lc($model->vendor.'_fielddev_config_process'));
    if ( $method ) {
        $result->{content_type} //= 'application/octet-stream';
        $method->(\$processed_data, $result, 'field_device' => $dev, 'vars' => $vars );
    }else{
        $result->{content_type} //= $dev->profile->config->content_type;
    }
    return $result;
}

sub dev_field_bootstrap :Chained('/') :PathPart('device/autoprov/bootstrap') :Args() {
    my ($self, $c, @id) = @_;
    my $opt = $c->req->params->{opt};
    my $id;

    delete $c->response->cookies->{ngcp_panel_session};
    $c->response->headers->remove_header('Connection');
    $c->response->headers->remove_header('X-Catalyst');
    $c->response->headers->push_header('Last-Modified' => DateTime::Format::HTTP->format_datetime());


    foreach my $did (@id) {
        $c->log->debug("checking bootstrap path part '$did'");
        $did =~ s/\.cfg$//;
        $did =~ s/\.ini$//;
        $did =~ s/^([^\=]+)\=0$/$1/;
        $did = lc $did;
        $did =~ s/\-[a-z]+$//;
        $did =~ s/\-//g;
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
    my $schema = 'https';
    my $host = $c->config->{deviceprovisioning}->{host} // $c->req->uri->host;
    my $port = $c->config->{deviceprovisioning}->{port} // 1444;
    my $boot_port = $c->config->{deviceprovisioning}->{bootstrap_port} // 1445;

    my $vars = {
        opt => $opt,
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
            booturl => "http://" . $c->req->uri->host . ":" .
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
    my $t = Template->new({
        PLUGIN_BASE => 'NGCP::Panel::Template::Plugin',
    });
    $t->process(\$data, $vars, \$processed_data) || do {
        my $error = $t->error();
        my $msg = "error processing template, type=".$error->type.", info='".$error->info."'";
        $c->log->error($msg);
        $c->response->body("500 - error creating template:\n$msg");
        $c->response->status(500);
        return;
    };
    if($model->vendor eq "Audiocodes") {
        $processed_data .= "\r\n\r\n";
    }

    $c->log->debug("providing config to $id");
    $c->log->debug($processed_data);

    my $result = $self->dev_field_encrypt( $c, $dev, $processed_data, $vars);
    $c->response->content_type($result->{content_type});
    $c->response->body(${$result->{content}});
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

    my $sub;
    if($c->config->{deviceprovisioning}->{softphone_webauth}) {
        $sub = $c->model('DB')->resultset('provisioning_voip_subscribers')->find({
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
    } else {
        $sub = $c->model('DB')->resultset('provisioning_voip_subscribers')->find({
           username => $user,
           'domain.domain' => $domain,
           password => $pass,
        },{
            join => 'domain',
        });
        unless($sub) {
            if($c->config->{features}->{debug}) {
                $c->response->body("404 - sipuser authentication failed");
            } else {
                $c->response->body("404 - invalid user config parameters");
            }
            $c->response->status(404);
            return;
        }
    }

    my $jitsi_prov;
    my $jitsi_prov_usr = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c,
        prov_subscriber => $sub,
        attribute => 'softphone_autoprov',
    );
    my $jitsi_prov_dom = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
        c => $c,
        prov_domain => $sub->domain,
        attribute => 'softphone_autoprov',
    );
    my $jitsi_prov_prof;
    if($sub->voip_subscriber_profile) {
        $jitsi_prov_prof = NGCP::Panel::Utils::Preferences::get_prof_preference_rs(
            c => $c,
            profile => $sub->voip_subscriber_profile,
            attribute => 'softphone_autoprov',
        );
    }
    if($jitsi_prov_usr->first && $jitsi_prov_usr->first->value) {
        $jitsi_prov = 1;
    } elsif($jitsi_prov_prof && $jitsi_prov_prof->first && $jitsi_prov_prof->first->value) {
        $jitsi_prov = 1;
    } elsif($jitsi_prov_dom->first && $jitsi_prov_dom->first->value) {
        $jitsi_prov = 1;
    } else {
        $jitsi_prov = 0;
    }
    unless($jitsi_prov) {
        if($c->config->{features}->{debug}) {
            $c->response->body("403 - softphone auto provisioning disabled via softphone_autoprov preference");
        } else {
            $c->response->body("403 - autoprov disabled");
        }
        $c->response->status(403);
        return;
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
net.java.sip.communicator.impl.protocol.sip.$sipacc.IS_CALL_PARK_ENABLED=true
net.java.sip.communicator.impl.protocol.sip.$sipacc.CALL_PARK_PREFIX_PROPERTY=*97*
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
net.java.sip.communicator.plugin.accountinfo.ACCOUNT_INFO_TOOLS_MENU_DISABLED_PROP=true
net.java.sip.communicator.plugin.connectioninfo.CONNECT_INFO_TOOLS_MENU_DISABLED_PROP=true
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
    NGCP::Panel::Utils::DeviceFirmware::get_firmware_data_into_body(
        c => $c,
        fw_id => $fw->id
    );
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

sub dev_field_firmware_next :Chained('dev_field_firmware_version_base') :PathPart('next') :Args {
    my ($self, $c, $tmp) = @_;

    my $rs = $c->stash->{fw_rs}->search({
        device_id => $c->stash->{dev}->profile->config->device->id,
        version => { '>' => $c->stash->{dev_fw_string} },
    }, {
        order_by => { -asc => 'version' },
    });
    if(defined $c->req->params->{q}) {
        $rs = $rs->search({
            version => { 'like' => $c->req->params->{q} . '%' },
        });
    }

    my $fw = $rs->first;
    unless($fw) {
        $c->response->content_type('text/plain');
        $c->response->body("404 - current firmware version '" . $c->stash->{dev_fw_string} . "' is latest");
        $c->response->status(404);
        return;
    }

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $fw->filename . '"');
    $c->response->content_type('application/octet-stream');
    NGCP::Panel::Utils::DeviceFirmware::get_firmware_data_into_body(
        c => $c,
        fw_id => $fw->id
    );
}

sub dev_field_firmware_latest :Chained('dev_field_firmware_version_base') :PathPart('latest') :Args {
    my ($self, $c, $tag) = @_;

    my $rs = $c->stash->{fw_rs}->search({
        device_id => $c->stash->{dev}->profile->config->device->id,
        version => { '>' => $c->stash->{dev_fw_string} },
    }, {
        order_by => { -desc => 'version' },
    });
    if(defined $tag && length $tag > 0) {
        $rs = $rs->search({
            tag => $tag,
        });
    }
    if(defined $c->req->params->{q}) {
        $rs = $rs->search({
            version => { 'like' => $c->req->params->{q} . '%' },
        });
    }

    my $fw = $rs->first;
    unless($fw) {
        $c->response->content_type('text/plain');
        $c->response->body("404 - current firmware version '" . $c->stash->{dev_fw_string} . "' is latest");
        $c->response->status(404);
        return;
    }

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $fw->filename . '"');
    $c->response->content_type('application/octet-stream');
    NGCP::Panel::Utils::DeviceFirmware::get_firmware_data_into_body(
        c => $c,
        fw_id => $fw->id
    );
}

sub devices_preferences_list :Chained('devmod_base') :PathPart('preferences') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $dev_pref_rs = NGCP::Panel::Utils::Preferences::get_preferences_rs(
        c => $c,
        type => 'dev',
        id => $c->stash->{devmod}->id,
    );

    my $pref_values = get_inflated_columns_all($dev_pref_rs,'hash' => 'attribute', 'column' => 'value', 'force_array' => 1);

    NGCP::Panel::Utils::Preferences::load_preference_list(
        c => $c,
        pref_values => $pref_values,
        #we don't need fielddev_pref flag, because it always will be just more narrow than dev_pref.
        dev_pref => 1,
        search_conditions => [{
            'attribute' =>
                [ -or =>
                    { 'like' => 'vnd_'.lc($c->stash->{devmod}->vendor).'%' },
                    {'-not_like' => 'vnd_%' },
                ],
            #relation type is defined by preference flag dev_pref,
            #so here we select only linked to the current model, or not linked to any model at all
            '-or' => [
                    'voip_preference_relations.autoprov_device_id' => $c->stash->{devmod}->id,
                    'voip_preference_relations.reseller_id' => $c->stash->{devmod}->reseller_id,
                    'voip_preference_relations.voip_preference_id' => undef
                ],
            },{
                join => {'voip_preferences' => 'voip_preference_relations'},
            }
        ]
    );

    $c->stash(template => 'device/preferences.tt');
    return;
}

sub devices_preferences_root :Chained('devices_preferences_list') :PathPart('') :Args(0) {
    return;
}

sub devices_preferences_base :Chained('devices_preferences_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;

    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
            -or => ['voip_preferences_enums.dev_pref' => 1,
                'voip_preferences_enums.dev_pref' => undef],
        },{
            prefetch => 'voip_preferences_enums',
        })
        ->find({id => $pref_id});

    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_dev_preferences')
        ->search({
            'attribute_id' => $pref_id,
            'device_id'    => $c->stash->{devmod}->id,
        });
    return;
}

sub devices_preferences_create :Chained('devices_preferences_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Preference", $c);

    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $resource = $form->values;

                $resource->{dev_pref}  = 1;
                $resource->{autoprov_device_id}  = $c->stash->{devmod}->id;

                my $preference = NGCP::Panel::Utils::Preferences::create_dynamic_preference(
                    $c, $resource,
                    group_name => 'CPBX Device Administration',
                );

                $c->session->{created_objects}->{preference} = { id => $preference->id };
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully created device model preference'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to create device model preference'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
    $c->stash(
        create_flag => 1,
        form => $form,
    );
}

sub devices_preferences_editmeta :Chained('devices_preferences_base') :PathPart('editmeta') :Args(0) {
    my ($self, $c) = @_;
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Preference", $c);

    my $params = { $c->stash->{preference_meta}->get_inflated_columns };
    $params->{enum} = [ map { {$_->get_inflated_columns} } $c->stash->{preference_meta}->voip_preferences_enums->all ];
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $resource = $form->values;

                $resource->{dev_pref}  = 1;
                $resource->{autoprov_device_id}  = $c->stash->{devmod}->id;

                NGCP::Panel::Utils::Preferences::update_dynamic_preference(
                    $c, $c->stash->{preference_meta}, $resource
                );
             });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Successfully updated device model preference'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to update device model preference'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
    $c->stash(
        editmeta_flag => 1,
        form => $form,
    );
}

sub devices_preferences_delete :Chained('devices_preferences_base') :PathPart('delete') :Args(0):Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    try {
        NGCP::Panel::Utils::Preferences::delete_dynamic_preference(
            $c, $c->stash->{preference_meta}
        );
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { id => $c->stash->{preference_meta}->id,
                      attribute => $c->stash->{preference_meta}->attribute },
            desc => $c->loc('Device model preference successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "failed to delete device model preference with id '".$c->stash->{preference_meta}->id."': $e",
            desc => $c->loc('Failed to delete device model preference'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
}


sub devices_preferences_edit :Chained('devices_preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->all;

    my $pref_rs = $c->stash->{devmod}->voip_dev_preferences;
    NGCP::Panel::Utils::Preferences::create_preference_form(
        c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $c->uri_for_action('/device/devices_preferences_root', [@{ $c->req->captures }[0]] ),
        edit_uri => $c->uri_for_action('/device/devices_preferences_edit', $c->req->captures ),
    );
    return;
}

sub profile_preferences_list :Chained('devprof_base') :PathPart('preferences') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $devprof_pref_rs = NGCP::Panel::Utils::Preferences::get_preferences_rs(
        c => $c,
        type => 'devprof',
        id => $c->stash->{devprof}->id,
    );
    my $pref_values = get_inflated_columns_all($devprof_pref_rs,'hash' => 'attribute', 'column' => 'value', 'force_array' => 1);

    NGCP::Panel::Utils::Preferences::load_preference_list(
        c => $c,
        pref_values => $pref_values,
        'devprof_pref' => 1,
        search_conditions => {
            '-or' => [
                {'attribute' => {'like' => 'vnd_'.lc($c->stash->{devprof}->config->device->vendor).'%' } },
                {'attribute' => {'-not_like' => 'vnd_%' }}
            ],
        }
    );

    $c->stash(template => 'device/profilepreferences.tt');
    return;
}

sub profile_preferences_root :Chained('profile_preferences_list') :PathPart('') :Args(0) {
    return;
}

sub profile_preferences_base :Chained('profile_preferences_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;

    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
            -or => ['voip_preferences_enums.devprof_pref' => 1,
                'voip_preferences_enums.devprof_pref' => undef],
        },{
            prefetch => 'voip_preferences_enums',
        })
        ->find({id => $pref_id});

    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_devprof_preferences')
        ->search({
            'attribute_id' => $pref_id,
            'profile_id'    => $c->stash->{devprof}->id,
        });
    return;
}

sub profile_preferences_edit :Chained('profile_preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->all;

    my $pref_rs = $c->stash->{devprof}->voip_devprof_preferences;
    NGCP::Panel::Utils::Preferences::create_preference_form(
        c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $c->uri_for_action('/device/profile_preferences_root', [@{ $c->req->captures }[0]] ),
        edit_uri => $c->uri_for_action('/device/profile_preferences_edit', $c->req->captures ),
    );
    return;
}

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Device

=head1 DESCRIPTION

A helper to manipulate devices data

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
