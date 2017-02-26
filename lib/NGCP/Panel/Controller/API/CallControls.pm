package NGCP::Panel::Controller::API::CallControls;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);

use NGCP::Panel::Utils::Sems;

require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/POST OPTIONS/];
}

sub api_description {
    return 'Allows to place calls via the API.';
};

sub query_params {
    return [
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallControls/;

sub resource_name{
    return 'callcontrols';
}
sub dispatch_path{
    return '/api/callcontrols/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-callcontrols';
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
            exceptions => [qw/subscriber_id/],
        );

        my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            'me.id' => $resource->{subscriber_id},
            'me.status' => { '!=' => 'terminated' },
        });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $subscriber_rs = $subscriber_rs->search({
                'contact.reseller_id' => $c->user->reseller_id,
            },{
                join => { contract => 'contact' },
            });
        }
        my $subscriber = $subscriber_rs->first;
        unless($subscriber) {
            $c->log->error("invalid subscriber id $$resource{subscriber_id} for outbound call");
            $self->error($c, HTTP_NOT_FOUND, "Calling subscriber not found.");
            last;
        }

        my ($callee_user, $callee_domain) = split /\@/, $resource->{destination};
        $callee_domain //= $subscriber->domain->domain;

        try {
            NGCP::Panel::Utils::Sems::dial_out($c, $subscriber->provisioning_voip_subscriber,
                $callee_user, $callee_domain);
        } catch($e) {
            $c->log->error("failed to dial out: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create call.");
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
