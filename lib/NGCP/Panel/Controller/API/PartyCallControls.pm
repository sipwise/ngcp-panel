package NGCP::Panel::Controller::API::PartyCallControls;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);

use NGCP::Panel::Utils::Sems;
use NGCP::Panel::Utils::SMS;

require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

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

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::PartyCallControls/;

sub resource_name{
    return 'partycallcontrols';
}
sub dispatch_path{
    return '/api/partycallcontrols/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-partycallcontrols';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

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

        if ($resource->{type} eq "pcc") {
            try {
                NGCP::Panel::Utils::Sems::party_call_control($c, $resource);
            } catch($e) {
                $c->log->error("failed to handle a party call control request: $e");
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR,
                    "Failed to handle a party call control request.");
                last;
            }
        } elsif ($resource->{type} eq "sms") {
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
                $c->log->error("failed to find sms with id $callid and token $token");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                    "Failed to find sms with callid $callid and given token");
                last;
            }
            if($status eq "ACCEPT") {
                $c->log->info("status for pcc sms of $callid is $status, forward sms");
                try {
                    NGCP::Panel::Utils::SMS::send_sms(
                        c => $c,
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
                $c->log->info("status for pcc sms of $callid is $status, don't forward sms");
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

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
