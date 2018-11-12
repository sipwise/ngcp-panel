package NGCP::Panel::Controller::TimeSet;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::TimeSet;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('timeset') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{timesets_rs} = $c->model('DB')->resultset('voip_time_sets');
    unless($c->user->roles eq "admin") {
        $c->stash->{timesets_rs} = $c->stash->{timesets_rs}->search({
            reseller_id => $c->user->reseller_id
        });
    }
    $c->stash->{timeset_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        $c->user->roles eq "admin"
            ? { name => 'reseller.name', search => 1, title => $c->loc('Reseller') }
            : (),
        { name => 'name', search => 1, title => $c->loc('Name') },
    ]);

    $c->stash(template => 'timeset/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{timesets_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{timeset_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub fieldajax :Chained('list') :PathPart('fieldajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{timesets_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller_id', search => 1, title => $c->loc('Reseller #') },
        { name => 'name', search => 1, title => $c->loc('Name') },
    ]));
    $c->detach( $c->view("JSON") );
}

sub base :Chained('list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $timeset_id) = @_;

    unless($timeset_id && is_int($timeset_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid timeset enry id detected',
            desc  => $c->loc('Invalid timeset entry id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
    }

    my $rs = $c->stash->{timesets_rs}->find($timeset_id);
    unless(defined($rs)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Timeset entry does not exist',
            desc  => $c->loc('Timeset entry does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
    }
    $c->stash(
        timeset => {$rs->get_inflated_columns},
        timeset_rs => $rs
    );
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::Reseller", $c);
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
            my $resource = $form->values;
            if($c->user->roles eq "admin") {
                $resource->{reseller_id} = $form->values->{reseller}{id};
                delete $resource->{reseller};
            }  else {
                $resource->{reseller_id} = $c->user->reseller_id;
            }
            $c->model('DB')->schema->txn_do( sub {
                NGCP::Panel::Utils::TimeSet::create_timesets(
                    c => $c,
                    resource => $form->values,
                );
            });
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Timeset entry successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create timeset entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = NGCP::Panel::Utils::TimeSet::get_timeset(c => $c, timeset => $c->stash->{timeset_rs});
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Timeset::Reseller", $c);
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
            $c->model('DB')->schema->txn_do( sub {
                my $resource = $form->values;
                if($c->user->roles eq "admin") {
                    $resource->{reseller_id} = $form->values->{reseller}{id};
                    delete $resource->{reseller};
                }  else {
                    $resource->{reseller_id} = $c->user->reseller_id;
                }
                NGCP::Panel::Utils::TimeSet::update_timesets(
                    c => $c,
                    timeset => $c->stash->{timeset_rs},
                    resource => $resource,
                );
            });
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Timeset entry successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update timeset entry'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete_timeset :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{timeset_rs}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => $c->stash->{timeset},
            desc => $c->loc('Timeset entry successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete timeset entry'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/timeset'));
}

1;
