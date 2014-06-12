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

    my $devmod_rs = $c->model('DB')->resultset('autoprov_devices');
    if($c->user->roles eq 'reseller') {
        $devmod_rs = $devmod_rs->search({ reseller_id => $c->user->reseller_id });
    } elsif($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') {
        $devmod_rs = $devmod_rs->search({ reseller_id => $c->user->voip_subscriber->contract->contact->reseller_id });
    }
    $c->stash->{devmod_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'vendor', search => 1, title => $c->loc('Vendor') },
        { name => 'model', search => 1, title => $c->loc('Model') },
    ]);

    my $devfw_rs = $c->model('DB')->resultset('autoprov_firmwares');
    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $devfw_rs = $devfw_rs->search({
        	'device.reseller_id' => $c->user->voip_subscriber->contract->contact->reseller_id,
            }, { 
                join => 'device',
        });
    } elsif($c->user->roles eq "reseller") {
        $devfw_rs = $devfw_rs->search({
                'device.reseller_id' => $c->user->reseller_id
            }, { 
                join => 'device',
        });
    }

    $c->stash->{devfw_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'device.reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'device.vendor', search => 1, title => $c->loc('Device Vendor') },
        { name => 'device.model', search => 1, title => $c->loc('Device Model') },
        { name => 'filename', search => 1, title => $c->loc('Firmware File') },
        { name => 'version', search => 1, title => $c->loc('Version') },
    ]);

    my $devconf_rs = $c->model('DB')->resultset('autoprov_configs');
    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $devconf_rs = $devconf_rs->search({
        	'device.reseller_id' => $c->user->voip_subscriber->contract->contact->reseller_id,
            }, { 
                join => 'device',
        });
    } elsif($c->user->roles eq "reseller") {
        $devconf_rs = $devconf_rs->search({
                'device.reseller_id' => $c->user->reseller_id
            }, { 
                join => 'device',
        });
    }

    $c->stash->{devconf_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'device.reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'device.vendor', search => 1, title => $c->loc('Device Vendor') },
        { name => 'device.model', search => 1, title => $c->loc('Device Model') },
        { name => 'version', search => 1, title => $c->loc('Version') },
    ]);

    my $devprof_rs = $c->model('DB')->resultset('autoprov_profiles');
    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $devprof_rs = $devprof_rs->search({
        	'device.reseller_id' => $c->user->voip_subscriber->contract->contact->reseller_id,
            }, { 
                join => { 'config' => 'device' },
        });
    } elsif($c->user->roles eq "reseller") {
        $devprof_rs = $devprof_rs->search({
                'device.reseller_id' => $c->user->reseller_id
            }, { 
                join => { 'config' => 'device' },
        });
    }
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
    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $fielddev_rs = $fielddev_rs->search({
        	'device.reseller_id' => $c->user->voip_subscriber->contract->contact->reseller_id,
            }, { 
                join => { 'profile' => { 'config' => 'device' } },
        });
    } elsif($c->user->roles eq "reseller") {
        $fielddev_rs = $fielddev_rs->search({
                'device.reseller_id' => $c->user->reseller_id
            }, { 
                join => { 'profile' => { 'config' => 'device' } },
        });
    }
    $c->stash->{fielddev_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'identifier', search => 1, title => $c->loc('MAC Address / Identifier') },
        { name => 'profile.name', search => 1, title => $c->loc('Profile Name') },
        { name => 'contract.id', search => 1, title => $c->loc('Customer #') },
        { name => 'contract.contact.email', search => 1, title => $c->loc('Customer Email') },
    ]);


    $c->stash(
        devmod_rs   => $devmod_rs,
        devfw_rs   => $devfw_rs,
        devconf_rs   => $devconf_rs,
        devprof_rs   => $devprof_rs,
        fielddev_rs => $fielddev_rs,
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
                my $linerange = delete $form->params->{linerange};

                my $devmod = $schema->resultset('autoprov_devices')->create($form->params);

                foreach my $range(@{ $linerange }) {
                    delete $range->{id};
                    $devmod->autoprov_device_line_ranges->create($range);
                }

                delete $c->session->{created_objects}->{reseller};
                $c->session->{created_objects}->{device} = { id => $devmod->id };
                $c->flash(messages => [{type => 'success', text => $c->loc('Successfully created device model')}]);
            });
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

    $c->stash->{devmod} = $c->stash->{devmod_rs}->find($devmod_id);
    unless($c->stash->{devmod}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "device model with id '$devmod_id' not found",
            desc => $c->loc('Device model not found'),
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
        push @{ $params->{linerange} }, { $range->get_inflated_columns };
    }
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

                my $linerange = delete $form->params->{linerange};
                $c->stash->{devmod}->update($form->params);

                my @existing_range = ();
                my $range_rs = $c->stash->{devmod}->autoprov_device_line_ranges;
                foreach my $range(@{ $linerange }) {
                    next unless(defined $range);
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
                $c->flash(messages => [{type => 'success', text => 'Successfully updated device model'}]);
            });
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
                my $file = delete $form->params->{data};
                $form->params->{filename} = $file->filename;
                $form->params->{data} = $file->slurp;
                my $devmod = $c->stash->{devmod_rs}->find($form->params->{device}{id});
                my $devfw = $devmod->create_related('autoprov_firmwares', $form->params);
                delete $c->session->{created_objects}->{device};
                $c->session->{created_objects}->{firmware} = { id => $devfw->id };
                $c->flash(messages => [{type => 'success', text => $c->loc('Successfully created device firmware')}]);
            });
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

    $c->stash->{devfw} = $c->stash->{devfw_rs}->find($devfw_id);
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
        $c->flash(messages => [{type => 'success', text => $c->loc('Device firmware successfully deleted') }]);
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
                $form->params->{device_id} = $form->params->{device}{id};
                delete $form->params->{device};
                my $file = delete $form->params->{data};
                $form->params->{filename} = $file->filename;
                $form->params->{data} = $file->slurp;

                $c->stash->{devfw}->update($form->params);
                delete $c->session->{created_objects}->{device};
                $c->flash(messages => [{type => 'success', text => $c->loc('Successfully updated device firmware')}]);
            });
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
                my $devmod = $c->stash->{devmod_rs}->find($form->params->{device}{id});
                my $devconf = $devmod->create_related('autoprov_configs', $form->params);
                delete $c->session->{created_objects}->{device};
                $c->session->{created_objects}->{config} = { id => $devconf->id };
                $c->flash(messages => [{type => 'success', text => $c->loc('Successfully created device configuration')}]);
            });
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

    $c->stash->{devconf} = $c->stash->{devconf_rs}->find($devconf_id);
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
        $c->flash(messages => [{type => 'success', text => $c->loc('Device configuration successfully deleted') }]);
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
                $form->params->{device_id} = $form->params->{device}{id};
                delete $form->params->{device};

                $c->stash->{devconf}->update($form->params);
                delete $c->session->{created_objects}->{device};
                $c->flash(messages => [{type => 'success', text => $c->loc('Successfully updated device configuration')}]);
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
            'config.create' => $c->uri_for('/device/config/create'),
        },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->params->{config_id} = $form->params->{config}{id};
                delete $form->params->{config};

                $c->model('DB')->resultset('autoprov_profiles')->create($form->params);

                delete $c->session->{created_objects}->{config};
                $c->flash(messages => [{type => 'success', text => $c->loc('Successfully created device profile')}]);
            });
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


sub devprof_delete :Chained('devprof_base') :PathPart('delete') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    try {
        $c->stash->{devprof}->delete;
        $c->flash(messages => [{type => 'success', text => $c->loc('Device profile successfully deleted') }]);
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
                $form->params->{config_id} = $form->params->{config}{id};
                delete $form->params->{config};

                $c->stash->{devprof}->update($form->params);

                delete $c->session->{created_objects}->{config};
                $c->flash(messages => [{type => 'success', text => $c->loc('Successfully updated device profile')}]);
            });
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

    my $schema = $c->config->{deviceprovisioning}->{secure} ? 'https' : 'http';
    my $host = $c->config->{deviceprovisioning}->{host} // $c->req->uri->host;
    my $port = $c->config->{deviceprovisioning}->{port} // 1444;

    if($id =~ /^[a-fA-F0-9]{12}\.cfg$/
       && $c->req->user_agent =~ /PolycomVVX/
    ) {
        $id =~ s/\.cfg$//;
        $c->response->content_type('text/xml');
        $c->response->body(
            '<?xml version="1.0" standalone="yes"?>'.
            '<APPLICATION '.
#           '  APP_FILE_PATH="sip.ld" '.
            '  CONFIG_FILES="'.$id.'-phone.cfg" '.
#           '  MISC_FILES="huji-polycom-501.bmp" '.
            '  LOG_FILE_DIRECTORY="" '.
            '/>'
        );
        return;
    }

    $id =~ s/^([^\=]+)\=0$/$1/;
    $id = lc $id;
    $id =~ s/\-phone\.cfg$//; # polycoms send a -phone.cfg suffix

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

    my $model = $dev->profile->config->device;

    my $vars = {
        config => {
            url => "$schema://$host:$port/device/autoprov/config/$id",
        },
        firmware => {
        },
        phone => {
            stationname => $dev->station_name,
            lineranges => [],
        },
        directory => {
            spaurl => "$schema://$host:$port/pbx/directory/spa/$id",
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
            # TODO: only push password for private/shared line?
            push @{ $range->{lines} }, {
                extension => $sub->pbx_extension,
                username => $sub->username,
                domain => $sub->domain->domain,
                password => $sub->password,
                displayname => $display_name,
                keynum => $line->key_num,
                type => $line->line_type,
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

    $c->response->content_type($dev->profile->config->content_type);
    $c->response->body($processed_data);
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
    my ($user, $domain) = split /\@/, $uri;
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

sub dev_field_firmware_version_base :Chained('dev_field_firmware_base') :PathPart('from') :CaptureArgs(1) {
    my ($self, $c, $fwver) = @_;

    unless($fwver) {
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
