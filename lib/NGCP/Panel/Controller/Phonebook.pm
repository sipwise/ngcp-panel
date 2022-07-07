package NGCP::Panel::Controller::Phonebook;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Phonebook;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    my $ngcp_type = $c->config->{general}{ngcp_type} // '';
    if ($ngcp_type ne 'sppro' && $ngcp_type ne 'carrier') {
        $c->detach('/error_page');
    }
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('phonebook') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{phonebook_rs} = $c->model('DB')->resultset('reseller_phonebook');
    unless($c->user->roles eq "admin") {
        $c->stash->{phonebook_rs} = $c->stash->{phonebook_rs}->search({
            reseller_id => $c->user->reseller_id
        });
    }
    $c->stash->{phonebook_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        $c->user->roles eq "admin"
            ? { name => 'reseller.name', search => 1, title => $c->loc('Reseller') }
            : (),
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'number', search => 1, title => $c->loc('Number') },
    ]);

    $c->stash(template => 'phonebook/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{phonebook_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{phonebook_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub base :Chained('list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $pb_id) = @_;

    unless($pb_id && is_int($pb_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid phonebook enry id detected',
            desc  => $c->loc('Invalid phonebook entry id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/phonebook'));
    }

    my $res = $c->stash->{phonebook_rs}->find($pb_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Phonebook entry does not exist',
            desc  => $c->loc('Phonebook entry does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/phonebook'));
    }
    $c->stash(phonebook_result => $res);
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Reseller", $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
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
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                delete $form->values->{reseller};
            } else {
                $form->values->{reseller_id} = $c->user->reseller_id;
            }
            $c->stash->{phonebook_rs}->create($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Phonebook entry successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create phonebook entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/phonebook'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{phonebook_result}->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Reseller", $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
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
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                delete $form->values->{reseller};
            }
            $c->stash->{phonebook_result}->update($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Phonebook entry successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update phonebook entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/phonebook'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete_phonebook :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{phonebook_result}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{phonebook_result}->get_inflated_columns },
            desc => $c->loc('Phonebook entry successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete phonebook entry'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/phonebook'));
}

sub upload_csv :Chained('list') :PathPart('upload_csv') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Upload", $c);
    NGCP::Panel::Utils::Phonebook::ui_upload_csv(
        $c, $c->stash->{phonebook_rs}, $form, 'reseller', $c->user->reseller_id,
        $c->uri_for('/phonebook/upload_csv'), $c->uri_for('/phonebook')
    );

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
    return;
}

sub download_csv :Chained('list') :PathPart('download_csv') :Args(0) {
    my ($self, $c) = @_;

    $c->response->header ('Content-Disposition' => 'attachment; filename="reseller_phonebook_entries.csv"');
    $c->response->content_type('text/csv');
    $c->response->status(200);
    NGCP::Panel::Utils::Phonebook::download_csv(
        $c, $c->stash->{phonebook_rs}, 'reseller', $c->user->reseller_id
    );
    return;
}

1;
