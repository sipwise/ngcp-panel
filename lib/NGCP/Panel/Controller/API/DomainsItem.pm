package NGCP::Panel::Controller::API::DomainsItem;
use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API::Domains';

class_has('resource_name', is => 'ro', default => 'domains');
class_has('dispatch_path', is => 'ro', default => '/api/domains/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-domains');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $domain = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, domain => $domain);

        my $hal = $self->hal_from_item($c, $domain);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
                $_
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $domain = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, domain => $domain);

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            unless($domain->domain_resellers->reseller_id == $c->user->reseller_id) {
                $self->error($c, HTTP_FORBIDDEN, "Domain does not belong to reseller");
                last;
            }
        }

        my $prov_domain = $domain->provisioning_voip_domain;
        if ($prov_domain) {
            $prov_domain->voip_dbaliases->delete;
            $prov_domain->voip_dom_preferences->delete;
            $prov_domain->provisioning_voip_subscribers->delete;
            $prov_domain->delete;
        }
        $domain->delete;

        try {
            unless($c->config->{features}->{debug}) {
                $self->xmpp_domain_disable($c, $domain);
                $self->sip_domain_reload($c);
            }
        } catch($e) {
            $c->log->error("failed to deactivate domain: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to deactivate domain.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
