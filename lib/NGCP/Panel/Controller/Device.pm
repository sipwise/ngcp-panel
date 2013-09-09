package NGCP::Panel::Controller::Device;
use Sipwise::Base;

use NGCP::Panel::Form::Device::Model;
use NGCP::Panel::Form::Device::ModelAdmin;
use NGCP::Panel::Utils::Navigation;


BEGIN { extends 'Catalyst::Controller'; }

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub base :Chained('/') :PathPart('device') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $devmod_rs = $c->model('DB')->resultset('autoprov_devices');
    unless($c->user->is_superuser) {
        $devmod_rs = $devmod_rs->search({ reseller_id => $c->user->reseller_id });
    }

    $c->stash->{devmod_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => '#' },
        { name => 'reseller.name', search => 1, title => 'Reseller' },
        { name => 'vendor', search => 1, title => 'Vendor' },
        { name => 'model', search => 1, title => 'Model' },
    ]);

    $c->stash(
        devmod_rs   => $devmod_rs,
        template => 'device/list.tt',
    );
}

sub root :Chained('base') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub devmod_ajax :Chained('base') :PathPart('model/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{devmod_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{devmod_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub devmod_create :Chained('base') :PathPart('model/create') :Args(0) {
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

                $schema->resultset('autoprov_devices')->create($form->params);
                delete $c->session->{created_objects}->{reseller};
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
        create_flag => 1,
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

sub devmod_delete :Chained('devmod_base') :PathPart('delete') :Args(0) {
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

sub devmod_edit :Chained('devmod_base') :PathPart('edit') :Args(0) {
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
        edit_flag => 1,
        form => $form,
    );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Domain - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 dom_list

basis for the domain controller

=head2 root

=head2 create

Provide a form to create new domains. Handle posted data and create domains.

=head2 search

obsolete

=head2 base

Fetch a domain by its id.

Data that is put on stash: domain, domain_result

=head2 edit

probably obsolete

=head2 delete

deletes a domain (defined in base)

=head2 ajax

Get domains and output them as JSON.

=head2 preferences

Show a table view of preferences.

=head2 preferences_base

Get details about one preference for further editing.

Data that is put on stash: preference_meta, preference, preference_values

=head2 preferences_edit

Use a form for editing one preference. Execute the changes that are posted.

Data that is put on stash: edit_preference, form

=head2 load_preference_list

Retrieves and processes a datastructure containing preference groups, preferences and their values, to be used in rendering the preference list.

Data that is put on stash: pref_groups

=head2 _sip_domain_reload

Ported from ossbss

reloads domain cache of sip proxies

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
