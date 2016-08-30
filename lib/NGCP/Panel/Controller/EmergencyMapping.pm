package NGCP::Panel::Controller::EmergencyMapping;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::EmergencyMapping;
use NGCP::Panel::Utils::MySQL;

use NGCP::Panel::Form::EmergencyMapping::Container;
use NGCP::Panel::Form::EmergencyMapping::ContainerAdmin;
use NGCP::Panel::Form::EmergencyMapping::Mapping;
use NGCP::Panel::Form::EmergencyMapping::Upload;
use NGCP::Panel::Form::EmergencyMapping::UploadAdmin;
use NGCP::Panel::Form::EmergencyMapping::Download;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('emergencymapping') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $emergency_container_rs = $c->model('DB')->resultset('emergency_containers');
    if($c->user->roles eq "reseller") {
        $emergency_container_rs = $emergency_container_rs->search({
            reseller_id => $c->user->reseller_id
        });
    }
    $c->stash(emergency_container_rs => $emergency_container_rs);
    $c->stash->{emergency_container_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", "search" => 1, "title" => $c->loc("#") },
        { name => "reseller.name", "search" => 1, "title" => $c->loc("Reseller") },
        { name => "name", "search" => 1, "title" => $c->loc("Name") },
    ]);

    my $emergency_mapping_rs = $c->model('DB')->resultset('emergency_mappings');
    $c->stash(emergency_mapping_rs => $emergency_mapping_rs);
    $c->stash->{emergency_mapping_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", "search" => 1, "title" => $c->loc("#") },
        { name => "emergency_container.name", "search" => 1, "title" => $c->loc("Container") },
        { name => "emergency_container.reseller.name", "search" => 1, "title" => $c->loc("Reseller") },
        { name => "code", "search" => 1, "title" => $c->loc("Emergency Number") },
        { name => "prefix", "search" => 1, "title" => $c->loc("Emergency Prefix") },
    ]);

    $c->stash(template => 'emergencymapping/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub emergency_container_ajax :Chained('list') :PathPart('emergency_container_ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{emergency_container_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{emergency_container_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub emergency_mapping_ajax :Chained('list') :PathPart('emergency_mapping_ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{emergency_mapping_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{emergency_mapping_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub emergency_container_base :Chained('list') :PathPart('emergency_container') :CaptureArgs(1) {
    my ($self, $c, $emergency_container_id) = @_;

    unless($emergency_container_id && is_int($emergency_container_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $emergency_container_id },
            desc  => $c->loc('Invalid emergency mapping container id detected!'),
        );
        $c->flash(emergency_container_messages => delete $c->flash->{messages});
        $c->response->redirect($c->uri_for());
        return;
    }

    my $res = $c->stash->{emergency_container_rs}->find($emergency_container_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $emergency_container_id },
            desc  => $c->loc('Emergency mapping container does not exist!'),
        );
        $c->flash(emergency_container_messages => delete $c->flash->{messages});
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(emergency_container => {$res->get_inflated_columns});
    $c->stash(emergency_container_result => $res);
}

sub emergency_container_edit :Chained('emergency_container_base') :PathPart('edit') {
    my ($self, $c ) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = $c->stash->{emergency_container};
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->roles eq "reseller") {
        $form = NGCP::Panel::Form::EmergencyMapping::Container->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::EmergencyMapping::ContainerAdmin->new(ctx => $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        if($c->user->roles eq "reseller") {
            $form->values->{reseller_id} = $c->user->reseller_id;
        } else {
            $form->values->{reseller_id} = $form->values->{reseller}{id};
        }
        delete $form->values->{reseller};
        try {
            my $schema = $c->model('DB');

            if ($c->model('DB')->resultset('emergency_containers')->search({
                    reseller_id => $form->values->{reseller_id},
                    name => $form->values->{name}
                },undef)->count > 0) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    data => { name => $form->values->{name} },
                    desc  => $c->loc("Emergency mapping container with this name already exists for this reseller!"),
                );
                $c->flash(emergency_container_messages => delete $c->flash->{messages});
                NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
                return;
            }


            $schema->txn_do(sub {
                $c->stash->{emergency_container_result}->update($form->values);
            });

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Emergency mapping container successfully updated'),
            );
            $c->flash(emergency_container_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update emergency mapping container'),
            );
            $c->flash(emergency_container_messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
    }
    $c->stash( 'emergency_container_edit_flag'      => 1 );
    $c->stash( 'emergency_container_form'           => $form );
}

sub emergency_container_create :Chained('list') :PathPart('emergency_container_create') :Args(0) {
    my ($self, $c) = @_;

    my $schema = $c->model('DB');
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->roles eq "reseller") {
        $form = NGCP::Panel::Form::EmergencyMapping::Container->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::EmergencyMapping::ContainerAdmin->new(ctx => $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        if($c->user->roles eq "reseller") {
            $form->values->{reseller_id} = $c->user->reseller_id;
        } else {
            $form->values->{reseller_id} = $form->values->{reseller}{id};
        }
        delete $form->values->{reseller};
        try {
            if ($c->model('DB')->resultset('emergency_containers')->search({
                    reseller_id => $form->values->{reseller_id},
                    name => $form->values->{name}
                },undef)->count > 0) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    data => { name => $form->values->{name} },
                    desc  => $c->loc("Emergency mapping container with this name already exists for this reseller!"),
                );
                $c->flash(emergency_container_messages => delete $c->flash->{messages});
                NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
                return;
            }
            my $emergency_container = $c->model('DB')->resultset('emergency_containers')->create($form->values);

            $c->session->{created_objects}->{emergency_container} = { id => $emergency_container->id };
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Emergency mapping container successfully created'),
            );
            $c->flash(emergency_container_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create emergency mapping container'),
            );
            $c->flash(emergency_container_messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
    }

    $c->stash(emergency_container_create_flag => 1);
    $c->stash(emergency_container_form => $form);
}

sub emergency_container_delete :Chained('emergency_container_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    my $emergency_container = $c->stash->{emergency_container_result};

    my $emergency_mapping_count = $emergency_container->emergency_mappings->count;
    if ($emergency_mapping_count > 0) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc  => $c->loc("Emergency mapping container still linked to emergency mappings."),
        );
        $c->flash(emergency_container_messages => delete $c->flash->{messages});
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
        return;
    }

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            $emergency_container->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{emergency_container},
            desc => $c->loc('Emergency mapping container successfully deleted'),
        );
        $c->flash(emergency_container_messages => delete $c->flash->{messages});
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{emergency_container},
            desc  => $c->loc('Failed to delete emergency mapping container'),
        );
        $c->flash(emergency_container_messages => delete $c->flash->{messages});
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
}

sub emergency_mapping_base :Chained('list') :PathPart('emergency_mapping') :CaptureArgs(1) {
    my ($self, $c, $emergency_mapping_id) = @_;

    unless($emergency_mapping_id && is_int($emergency_mapping_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $emergency_mapping_id },
            desc  => $c->loc('Invalid emergency mapping id detected!'),
        );
        $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
        $c->response->redirect($c->uri_for());
        return;
    }

    my $res = $c->stash->{emergency_mapping_rs}->find($emergency_mapping_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $emergency_mapping_id },
            desc  => $c->loc('Emergency mapping does not exist!'),
        );
        $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(emergency_mapping => {$res->get_inflated_columns});
    $c->stash(emergency_mapping_result => $res);
}

sub emergency_mapping_edit :Chained('emergency_mapping_base') :PathPart('edit') {
    my ($self, $c ) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = $c->stash->{emergency_mapping};
    $params->{emergency_container}{id} = delete $params->{emergency_container_id};
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::EmergencyMapping::Mapping->new(ctx => $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => { 'emergency_container.create' => $c->uri_for('/emergencymapping/emergency_container_create') },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        $form->values->{emergency_container_id} = $form->values->{emergency_container}{id};
        delete $form->values->{emergency_container};
        my $emergency_container = $c->model('DB')->resultset('emergency_containers')->find($form->values->{emergency_container_id});
        unless($emergency_container) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                data => { id => $form->values->{emergency_container_id} },
                    desc  => $c->loc('Invalid emergency mapping container id detected!'),
                );
            $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
            return;
        }
        if ($c->model('DB')->resultset('emergency_mappings')->search({
                emergency_container_id => $emergency_container->id,
                code => $form->values->{code}
            },undef)->count > 0) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                data => { code => $form->values->{code} },
                desc  => $c->loc("Emergency code already defined for emergency mapping container!"),
            );
            $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
            return;
        }
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->values->{prefix} = undef unless(length $form->values->{prefix});
                $c->stash->{emergency_mapping_result}->update($form->values);
            });

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Emergency mapping successfully updated'),
            );
            $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update emergency mapping'),
            );
            $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
    }
    $c->stash( 'emergency_mapping_edit_flag'      => 1 );
    $c->stash( 'emergency_mapping_form'           => $form );
}

sub emergency_mapping_create :Chained('list') :PathPart('emergency_mapping_create') :Args(0) {
    my ($self, $c) = @_;

    my $schema = $c->model('DB');
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form = NGCP::Panel::Form::EmergencyMapping::Mapping->new(ctx => $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => { 'emergency_container.create' => $c->uri_for('/emergencymapping/emergency_container_create') },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        $form->values->{emergency_container_id} = $form->values->{emergency_container}{id};
        delete $form->values->{emergency_container};
        my $emergency_container = $c->model('DB')->resultset('emergency_containers')->find($form->values->{emergency_container_id});
        unless($emergency_container) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                data => { id => $form->values->{emergency_container_id} },
                desc  => $c->loc('Invalid emergency container id detected!'),
            );
            $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
            return;
        }
        if ($c->model('DB')->resultset('emergency_mappings')->search({
                emergency_container_id => $emergency_container->id,
                code => $form->values->{code}
            },undef)->count > 0) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                data => { code => $form->values->{code} },
                desc  => $c->loc("Emergency mapping already exists for this emergency mapping container!"),
            );
            $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
            return;
        }
        try {
            my $emergency_mapping = $emergency_container->emergency_mappings->create($form->values);
            $c->session->{created_objects}->{emergency_mapping} = { id => $emergency_mapping->id };
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Emergency mapping successfully created'),
            );
            $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create emergency mapping'),
            );
            $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
    }

    $c->stash(emergency_mapping_create_flag => 1);
    $c->stash(emergency_mapping_form => $form);
}

sub emergency_mapping_delete :Chained('emergency_mapping_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    my $emergency_mapping = $c->stash->{emergency_mapping_result};

    try {
        $emergency_mapping->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{emergency_mapping},
            desc => $c->loc('Emergency mapping successfully deleted'),
        );
        $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{emergency_mapping},
            desc  => $c->loc('Failed to delete emergency mapping'),
        );
        $c->flash(emergency_mapping_messages => delete $c->flash->{messages});
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emergencymapping'));
}



sub emergency_mappings_upload :Chained('list') :PathPart('upload') :Args(0) {
    my ($self, $c) = @_;

    my $form;
    if($c->user->roles eq "reseller") {
        $form = NGCP::Panel::Form::EmergencyMapping::Upload->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::EmergencyMapping::UploadAdmin->new(ctx => $c);
    }
    my $upload = $c->req->upload('upload_mapping');
    my $posted = $c->req->method eq 'POST';
    $c->request->params->{upload_mapping} = $posted ? $upload : undef;
    my $params = {};
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    if($form->validated) {

        # TODO: check by formhandler?
        unless($upload) {
            NGCP::Panel::Utils::Message::error(
                c    => $c,
                desc => $c->loc('No emergency mapping file specified!'),
            );
            $c->flash(emergency_container_messages => delete $c->flash->{messages});
            $c->response->redirect($c->uri_for('/emergencymapping'));
            return;
        }
        my $data = $upload->slurp;
        my($emergency_mappings, $fails, $text_success);
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                if($c->req->params->{purge_existing}) {
                    my ($start, $end);
                    $start = time;
                    my $rs = $c->stash->{emergency_container_rs}->search({
                        reseller_id => $form->params->{reseller}->{id}
                    });
                    $rs->delete;
                    $end = time;
                    $c->log->debug("Purging emergency mappings took " . ($end - $start) . "s");
                }
                ( $emergency_mappings, $fails, $text_success ) = NGCP::Panel::Utils::EmergencyMapping::upload_csv(
                    c       => $c,
                    data    => \$data,
                    schema  => $schema,
                    reseller_id => $form->params->{reseller}->{id},
                );
            });

            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $$text_success,
            );
            $c->flash(emergency_container_messages => delete $c->flash->{messages});
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to upload emergency mappings'),
            );
            $c->flash(emergency_container_messages => delete $c->flash->{messages});
        }

        $c->response->redirect($c->uri_for('/emergencymapping'));
        return;
    }

    $c->stash(emergency_container_create_flag => 1);
    $c->stash(emergency_container_form => $form);
}

sub emergency_mappings_download :Chained('list') :PathPart('download') :Args(0) {
    my ($self, $c) = @_;

    my $form;
    my $reseller_id;
    if($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    } else {
        $form = NGCP::Panel::Form::EmergencyMapping::Download->new(ctx => $c);
    }
    my $posted = $c->req->method eq 'POST';
    my $params = {};

    if(defined $form) {
        $form->process(
            posted => $posted,
            params => $c->request->params,
            item => $params,
        );
        if($form->validated) {
            $reseller_id = $form->params->{reseller}{id};
        }
    }

    if(!$posted || !defined $reseller_id) { 
        $c->stash(emergency_container_create_flag => 1);
        $c->stash(emergency_container_form => $form);
    } else {
        my $schema = $c->model('DB');
        $c->response->header ('Content-Disposition' => "attachment; filename=\"emergency_mapping_list_reseller_$reseller_id.csv\"");
        $c->response->content_type('text/csv');
        $c->response->status(200);
        NGCP::Panel::Utils::EmergencyMapping::create_csv(
            c => $c,
            reseller_id => $reseller_id,
        );
    }



    return;
}

__PACKAGE__->meta->make_immutable;

1;
