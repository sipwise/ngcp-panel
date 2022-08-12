package NGCP::Panel::Controller::API::DomainsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;
use NGCP::Panel::Utils::XMLDispatcher;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Domains/;

sub resource_name{
    return 'domains';
}

sub dispatch_path{
    return '/api/domains/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-domains';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller/],
        Journal => [qw/admin reseller/],
    }
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $domain = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, domain => $domain);

        my $hal = $self->hal_from_item($c, $domain);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r =~
                s/rel=self/rel="item self"/r;
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $domain = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, domain => $domain);

        my ($sip_reload, $xmpp_reload) = $self->check_reload($c, $c->req->params);

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            if ($domain->reseller_id != $c->user->reseller_id) {
                $self->error($c, HTTP_FORBIDDEN, "Domain does not belong to the reseller");
                last;
            }
        }

        last unless $self->add_delete_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            return $self->hal_from_item($c,$domain); });
        
        my $prov_domain = $domain->provisioning_voip_domain;
        if ($prov_domain) {
            $prov_domain->voip_dbaliases->delete;
            $prov_domain->voip_dom_preferences->delete;
            $prov_domain->provisioning_voip_subscribers->delete;
            $prov_domain->delete;
        }

        $domain->delete;

        $guard->commit;

        try {
            $self->xmpp_domain_disable($c, $domain->domain) if $xmpp_reload;
            NGCP::Panel::Utils::XMLDispatcher::sip_domain_reload($c) if $sip_reload;
        } catch($e) {
            $c->log->error("failed to deactivate domain: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to deactivate domain.");
            last;
        }

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
