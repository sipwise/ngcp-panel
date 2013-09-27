package NGCP::Panel::Controller::Device;
use Sipwise::Base;

use Template;
use NGCP::Panel::Form::Device::Model;
use NGCP::Panel::Form::Device::ModelAdmin;
use NGCP::Panel::Form::Device::Firmware;
use NGCP::Panel::Form::Device::Config;
use NGCP::Panel::Form::Device::Profile;
use NGCP::Panel::Utils::Navigation;


BEGIN { extends 'Catalyst::Controller'; }

sub auto {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub base :Chained('/') :PathPart('device') :CaptureArgs(0) {
    my ($self, $c) = @_;

    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);

    # TODO: move out fw/profile/config fetching to separate func to not 
    # load it for subscriber access?

    my $devmod_rs = $c->model('DB')->resultset('autoprov_devices');
    if($c->user->roles eq 'reseller') {
        $devmod_rs = $devmod_rs->search({ reseller_id => $c->user->reseller_id });
    } elsif($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') {
        $devmod_rs = $devmod_rs->search({ reseller_id => $c->user->voip_subscriber->contract->contact->reseller_id });
    }
    $c->stash->{devmod_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => '#' },
        { name => 'reseller.name', search => 1, title => 'Reseller' },
        { name => 'vendor', search => 1, title => 'Vendor' },
        { name => 'model', search => 1, title => 'Model' },
    ]);

    my $devfw_rs = $c->model('DB')->resultset('autoprov_firmwares');
    unless($c->user->is_superuser) {
        $devfw_rs = $devfw_rs->search({
                'device.reseller_id' => $c->user->reseller_id
            }, { 
                join => 'device',
        });
    }
    $c->stash->{devfw_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => '#' },
        { name => 'device.vendor', search => 1, title => 'Device Vendor' },
        { name => 'device.model', search => 1, title => 'Device Model' },
        { name => 'filename', search => 1, title => 'Firmware File' },
    ]);

    my $devconf_rs = $c->model('DB')->resultset('autoprov_configs');
    unless($c->user->is_superuser) {
        $devconf_rs = $devconf_rs->search({
                'device.reseller_id' => $c->user->reseller_id
            }, { 
                join => 'device',
        });
    }
    $c->stash->{devconf_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => '#' },
        { name => 'device.vendor', search => 1, title => 'Device Vendor' },
        { name => 'device.model', search => 1, title => 'Device Model' },
        { name => 'version', search => 1, title => 'Version' },
    ]);

    my $devprof_rs = $c->model('DB')->resultset('autoprov_profiles');
    unless($c->user->is_superuser) {
        $devprof_rs = $devprof_rs->search({
                'device.reseller_id' => $c->user->reseller_id
            }, { 
                join => 'device',
        });
    }
    $c->stash->{devprof_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => '#' },
        { name => 'name', search => 1, title => 'Name' },
        { name => 'config.device.vendor', search => 1, title => 'Device Vendor' },
        { name => 'config.device.model', search => 1, title => 'Device Model' },
        { name => 'firmware.filename', search => 1, title => 'Firmware File' },
        { name => 'config.version', search => 1, title => 'Configuration Version' },
    ]);

    $c->stash(
        devmod_rs   => $devmod_rs,
        devfw_rs   => $devfw_rs,
        devconf_rs   => $devconf_rs,
        devprof_rs   => $devprof_rs,
        template => 'device/list.tt',
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
                    $form->params->{reseller_id} = $form->params->{reseller}{id};
                } else {
                    $form->params->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->params->{reseller};

                my $ft = File::Type->new();
                if($form->params->{front_image}) {
                    my $front_image = delete $form->params->{front_image};
                    $form->params->{front_image} = $front_image->slurp;
                    $form->params->{front_image_type} = $ft->mime_type($form->params->{front_image});
                }
                if($form->params->{mac_image}) {
                    my $mac_image = delete $form->params->{mac_image};
                    $form->params->{mac_image} = $mac_image->slurp;
                    $form->params->{mac_image_type} = $ft->mime_type($form->params->{mac_image});
                }

                my $devmod = $schema->resultset('autoprov_devices')->create($form->params);
                delete $c->session->{created_objects}->{reseller};
                $c->session->{created_objects}->{device} = { id => $devmod->id };
                $c->flash(messages => [{type => 'success', text => 'Successfully created device model'}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => "Failed to create device model",
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devmod_create_flag => 1,
        form => $form,
    );
}

sub devmod_base :Chained('base') :PathPart('model') :CaptureArgs(1) {
    my ($self, $c, $devmod_id) = @_;

    unless($devmod_id->is_int) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid device model id '$devmod_id'",
            desc => "Invalid device model id",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devmod} = $c->stash->{devmod_rs}->find($devmod_id);
    unless($c->stash->{devmod}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "device model with id '$devmod_id' not found",
            desc => "Device model not found",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
}

sub devmod_delete :Chained('devmod_base') :PathPart('delete') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devmod}->delete;
        $c->flash(messages => [{type => 'success', text => 'Device model successfully deleted' }]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete device model with id '".$c->stash->{devmod}->id."': $e",
            desc => "Failed to delete device model",
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
}

sub devmod_edit :Chained('devmod_base') :PathPart('edit') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $c->stash->{devmod}->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Device::ModelAdmin->new;
    } else {
        $form = NGCP::Panel::Form::Device::Model->new;
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
                    $form->params->{reseller_id} = $form->params->{reseller}{id};
                } else {
                    $form->params->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->params->{reseller};

                if($form->params->{front_image}) {
                    my $front_image = delete $form->params->{front_image};
                    $form->params->{front_image} = $front_image->slurp;
                    $form->params->{front_image_type} = $front_image->type;
                } else {
                    delete $form->params->{front_image};
                    delete $form->params->{front_image_type};
                }

                if($form->params->{mac_image}) {
                    my $mac_image = delete $form->params->{mac_image};
                    $form->params->{mac_image} = $mac_image->slurp;
                    $form->params->{mac_image_type} = $mac_image->type;
                } else {
                    delete $form->params->{mac_image};
                    delete $form->params->{mac_image_type};
                }

                $c->stash->{devmod}->update($form->params);
                delete $c->session->{created_objects}->{reseller};
                $c->flash(messages => [{type => 'success', text => 'Successfully updated device model'}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => "Failed to update device model",
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devmod_edit_flag => 1,
        form => $form,
    );
}

sub devmod_download_frontimage :Chained('devmod_base') :PathPart('frontimage') :Args(0) {
    my ($self, $c) = @_;

    my $devmod = $c->stash->{devmod};
    unless($devmod->front_image) {
        $c->response->body("404 - No front image available for this device model");
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
        $c->response->body("404 - No mac image available for this device model");
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
                my $file = delete $form->params->{data};
                $form->params->{filename} = $file->filename;
                $form->params->{data} = $file->slurp;
                my $devmod = $c->stash->{devmod_rs}->find($form->params->{device}{id});
                my $devfw = $devmod->create_related('autoprov_firmwares', $form->params);
                delete $c->session->{created_objects}->{device};
                $c->session->{created_objects}->{firmware} = { id => $devfw->id };
                $c->flash(messages => [{type => 'success', text => 'Successfully created device firmware'}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => "Failed to create device firmware",
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
            desc => "Invalid device firmware id",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devfw} = $c->stash->{devfw_rs}->find($devfw_id);
    unless($c->stash->{devfw}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "device firmware with id '$devfw_id' not found",
            desc => "Device firmware not found",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
}

sub devfw_delete :Chained('devfw_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devfw}->delete;
        $c->flash(messages => [{type => 'success', text => 'Device firmware successfully deleted' }]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete device firmware with id '".$c->stash->{devfw}->id."': $e",
            desc => "Failed to delete device firmware",
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
                $form->params->{device_id} = $form->params->{device}{id};
                delete $form->params->{device};
                my $file = delete $form->params->{data};
                $form->params->{filename} = $file->filename;
                $form->params->{data} = $file->slurp;

                $c->stash->{devfw}->update($form->params);
                delete $c->session->{created_objects}->{device};
                $c->flash(messages => [{type => 'success', text => 'Successfully updated device firmware'}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => "Failed to update device firmware",
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
                my $devmod = $c->stash->{devmod_rs}->find($form->params->{device}{id});
                my $devconf = $devmod->create_related('autoprov_configs', $form->params);
                delete $c->session->{created_objects}->{device};
                $c->session->{created_objects}->{config} = { id => $devconf->id };
                $c->flash(messages => [{type => 'success', text => 'Successfully created device configuration'}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => "Failed to create device configuration",
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
            desc => "Invalid device configuration id",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devconf} = $c->stash->{devconf_rs}->find($devconf_id);
    unless($c->stash->{devconf}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "device configuration with id '$devconf_id' not found",
            desc => "Device configuration not found",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
}

sub devconf_delete :Chained('devconf_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devconf}->delete;
        $c->flash(messages => [{type => 'success', text => 'Device configuration successfully deleted' }]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete device configuration with id '".$c->stash->{devconf}->id."': $e",
            desc => "Failed to delete device configuration",
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
                $form->params->{device_id} = $form->params->{device}{id};
                delete $form->params->{device};

                $c->stash->{devconf}->update($form->params);
                delete $c->session->{created_objects}->{device};
                $c->flash(messages => [{type => 'success', text => 'Successfully updated device configuration'}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => "Failed to update device configuration",
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
            'firmware.create' => $c->uri_for('/device/firmware/create'),
            'config.create' => $c->uri_for('/device/config/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->params->{firmware_id} = $form->params->{firmware}{id} || undef;;
                delete $form->params->{firmware};
                $form->params->{config_id} = $form->params->{config}{id};
                delete $form->params->{config};

                $c->model('DB')->resultset('autoprov_profiles')->create($form->params);

                delete $c->session->{created_objects}->{firmware};
                delete $c->session->{created_objects}->{config};
                $c->flash(messages => [{type => 'success', text => 'Successfully created device profile'}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => "Failed to create device profile",
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devprof_create_flag => 1,
        form => $form,
    );
}

sub devprof_base :Chained('base') :PathPart('profile') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c, $devprof_id) = @_;

    unless($devprof_id->is_int) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid device profile id '$devprof_id'",
            desc => "Invalid device profile id",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash->{devprof} = $c->stash->{devprof_rs}->find($devprof_id);
    unless($c->stash->{devprof}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "device profile with id '$devprof_id' not found",
            desc => "Device profile not found",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }
}

sub devprof_delete :Chained('devprof_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devprof}->delete;
        $c->flash(messages => [{type => 'success', text => 'Device profile successfully deleted' }]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete device profile with id '".$c->stash->{devprof}->id."': $e",
            desc => "Failed to delete device profile",
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
}

sub devprof_edit :Chained('devprof_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $c->stash->{devprof}->get_inflated_columns };
    $params->{firmware}{id} = delete $params->{firmware_id};
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
            'firmware.create' => $c->uri_for('/device/firmware/create'),
            'config.create' => $c->uri_for('/device/config/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->params->{firmware_id} = $form->params->{firmware}{id} || undef;
                delete $form->params->{firmware};
                $form->params->{config_id} = $form->params->{config}{id};
                delete $form->params->{config};

                $c->stash->{devprof}->update($form->params);

                delete $c->session->{created_objects}->{firmware};
                delete $c->session->{created_objects}->{config};
                $c->flash(messages => [{type => 'success', text => 'Successfully updated device profile'}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => "Failed to update device profile",
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/device'));
    }

    $c->stash(
        devprof_edit_flag => 1,
        form => $form,
    );
}

sub dev_field_config :Chained('/') :PathPart('device/autoprov') :Args() {
    my ($self, $c, $id) = @_;

    unless($id) {
        $c->response->content_type('text/plain');
        $c->response->body("404 - device not found");
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
        $c->response->body("404 - device not found");
        $c->response->status(404);
        return;
    }

    my $sub = $dev->provisioning_voip_subscriber;
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
    my $vars = {
        sip => {
            username => $sub->username,
            password => $sub->password,
            domain => $sub->domain->domain,
            displayname => $display_name,
        },
    };

    my $data = $dev->profile->config->data;
    my $processed_data = "";
    my $t = Template->new;
    $t->process(\$data, $vars, \$processed_data);

    $c->response->content_type($dev->profile->config->content_type);
    $c->response->body($processed_data);
}

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
