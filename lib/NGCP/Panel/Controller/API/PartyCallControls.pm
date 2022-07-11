package NGCP::Panel::Controller::API::PartyCallControls;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


use NGCP::Panel::Utils::Sems;
use NGCP::Panel::Utils::SMS;
use NGCP::Panel::Utils::Preferences;


sub allowed_methods{
    return [qw/POST OPTIONS/];
}

sub api_description {
    return 'Allows to control queued calls and sms via the API.';
};

sub query_params {
    return [
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PartyCallControls/;

sub resource_name{
    return 'partycallcontrols';
}

sub dispatch_path{
    return '/api/partycallcontrols/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-partycallcontrols';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub POST :Allow {
    my ($self, $c) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        if ($resource->{type} eq "sms") {
            my $error_msg;
            my $callid = $resource->{callid};
            my $status = $resource->{status};
            my $token = $resource->{token};
            my $sms;
            try {
                if($c->user->roles eq "reseller") {
                    my $sms_rs = $c->model('DB')->resultset('sms_journal')->search({
                        'me.id' => $callid,
                        'pcc_status' => 'pending',
                        'contact.reseller_id' => $c->user->reseller_id,
                    },{
                        join => { 'provisioning_voip_subscriber' => { 'voip_subscriber' => { 'contract' => 'contact' } } }
                    });
                    $sms = $sms_rs->first;
                } else {
                    $sms = $c->model('DB')->resultset('sms_journal')->search({
                        'me.id' => $callid,
                        'pcc_token' => $token,
                        'pcc_status' => 'pending',
                    })->first;
                }
            } catch($e) {
                $c->log->error("failed to handle a party call control request: $e");
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR,
                    "Failed to handle a party call control request.");
                last;
            }
            unless($sms) {
                $c->log->error("failed to find sms with id " . $c->qs($callid) . " and token $token");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                    "Failed to find sms with callid " . $c->qs($callid) . " and given token");
                last;
            }
            if($status eq "ACCEPT") {
                $c->log->info("status for pcc sms of " . $c->qs($callid) . " is $status, forward sms");
                my $smsc_peer = '';
                my $smsc_peer_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                    c => $c, attribute => 'smsc_peer',
                    prov_domain => $sms->provisioning_voip_subscriber->domain,
                );
                if ($smsc_peer_rs && $smsc_peer_rs->first && $smsc_peer_rs->first->value) {
                    my $smsc_peer = $smsc_peer_rs->first->value;
                }
                try {
                    NGCP::Panel::Utils::SMS::send_sms(
                        c => $c,
                        smsc_peer => $smsc_peer,
                        caller => $sms->caller,
                        callee => $sms->callee,
                        text => $sms->text,
                        coding => $sms->coding,
                        err_code => sub {$error_msg = shift;},
                    );
                    $sms->update({ pcc_status => "complete" });
                } catch($e) {
                    $c->log->error("failed to handle a party call control request: $e");
                    $self->error($c, HTTP_INTERNAL_SERVER_ERROR,
                        "Failed to handle a party call control request.");
                    last;
                }
            } else {
                $c->log->info("status for pcc sms of " . $c->qs($callid) . " is $status, don't forward sms");
                try {
                    $sms->update({ pcc_status => "complete" });
                } catch($e) {
                    $c->log->error("failed to handle a party call control request: $e");
                    $self->error($c, HTTP_INTERNAL_SERVER_ERROR,
                        "Failed to handle a party call control request.");
                    last;
                }
            }
        } else {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                "Invalid party call control type, must be 'pcc' or 'sms'.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_OK);
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
