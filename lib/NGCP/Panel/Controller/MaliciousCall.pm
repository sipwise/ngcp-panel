package NGCP::Panel::Controller::MaliciousCall;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::MaliciousCall::Reseller;
use NGCP::Panel::Form::MaliciousCall::Admin;
use NGCP::Panel::Utils::Message;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub mcid_list :Chained('/') :PathPart('maliciouscall') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    if($c->user->roles eq "admin") {
        my $mcid_rs = $c->model('DB')->resultset('malicious_calls');
        $c->stash->{mcid_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
            { name => 'id', search => 1, title => $c->loc('#') },
            { name => 'subscriber.contract.contact.reseller.name', search => 1, title => $c->loc('Reseller') },
            { name => 'call_id', search => 1, title => $c->loc('Call-Id') },
            { name => 'caller', search => 1, title => $c->loc('Caller') },
            { name => 'callee', search => 1, title => $c->loc('Callee') },
            { name => 'start_time', search => 1, title => $c->loc('Called at') },
            { name => 'duration', search => 1, title => $c->loc('Duration') },
            { name => 'source', search => 1, title => $c->loc('Source') },
            { name => 'reported_at', search => 1, title => $c->loc('Reported at') },
        ]);
        $c->stash->{mcid_rs} = $mcid_rs;
    } elsif($c->user->roles eq "reseller") {
        my $mcid_rs = $c->model('DB')->resultset('malicious_calls')
        ->search({
            'reseller.id' => $c->user->reseller_id,
        },{
            join => { 'subscriber' => { 'contract' => { 'contact' => 'reseller' } } },
        });
        #my $mcid_rs = $mcid_rs->search({
        #    reseller_id => $c->user->reseller_id,
        #});
        $c->stash->{mcid_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
            { name => 'id', search => 1, title => $c->loc('#') },
            { name => 'call_id', search => 1, title => $c->loc('Call-Id') },
            { name => 'caller', search => 1, title => $c->loc('Caller') },
            { name => 'callee', search => 1, title => $c->loc('Callee') },
            { name => 'start_time', search => 1, title => $c->loc('Called at') },
            { name => 'duration', search => 1, title => $c->loc('Duration') },
            { name => 'source', search => 1, title => $c->loc('Source') },
            { name => 'reported_at', search => 1, title => $c->loc('Reported at') },
        ]);
        $c->stash->{mcid_rs} = $mcid_rs;
    }
    $c->stash(template => 'maliciouscall/list.tt');
}

sub root :Chained('mcid_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('mcid_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $rs = $c->stash->{mcid_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{mcid_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub base :Chained('mcid_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $mcid_id) = @_;

    unless($mcid_id && $mcid_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            log => 'Invalid malicious call id detected',
            desc => $c->log('Invalid malicious call id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{mcid_rs}->find($mcid_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            log => 'Malicious call does not exist',
            desc => $c->log('Malicious call does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash->{mcid_res} = $res;
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if(($c->user->roles eq "admin" || $c->user->roles eq "reseller") && $c->user->read_only);

    try {
        $c->stash->{mcid_res}->delete;
        NGCP::Panel::Utils::Message->info(
            c => $c,
            desc  => $c->loc('Malicious call successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            data => { id => $$c->stash->{mcid_res}->id },
            desc  => $c->loc('Failed to delete Malicious call'),
        );
    }
    $c->response->redirect($c->uri_for());
}

__PACKAGE__->meta->make_immutable;
1;
# vim: set tabstop=4 expandtab:
