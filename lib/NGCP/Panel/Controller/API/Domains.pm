package NGCP::Panel::Controller::API::Domains;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::XMLDispatcher;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Specifies a SIP Domain to be used as host part for SIP <a href="#subscribers">Subscribers</a>. You need a domain before you can create a subscriber. Multiple domains can be created. A domain could also be an IPv4 or IPv6 address (whereas the latter needs to be enclosed in square brackets, e.g. [::1]).';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for domains belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'domain_resellers.reseller_id' => $q };
                },
                second => sub {
                    { join => 'domain_resellers' };
                },
            },
        },
        {
            param => 'domain',
            description => 'Filter for domains matching the given pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { domain => { like => $q } };
                },
                second => sub { },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Domains/;

sub resource_name{
    return 'domains';
}

sub dispatch_path{
    return '/api/domains/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-domains';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $domains = $self->item_rs($c);
        (my $total_count, $domains) = $self->paginate_order_collection($c, $domains);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $domain ($domains->all) {
            push @embedded, $self->hal_from_item($c, $domain, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $domain->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $rname = $self->resource_name;

        my $response = HTTP::Response->new(HTTP_OK, undef, 
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
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
        my ($sip_reload, $xmpp_reload) = $self->check_reload($c, $resource);

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        #form for the reseller role doesn't have field reseller.
        if($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }
        my $reseller = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id});
        unless($reseller) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id', doesn't exist.");
            last;
        }

        my $billing_domain;
        $billing_domain = $c->model('DB')->resultset('domains')->find({
            domain => $resource->{domain},
        });
        if($billing_domain) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Domain '".$resource->{domain}."' already exists.");
            last;
        }
        
        try {
            my $rs = $self->item_rs($c);
            $billing_domain = $c->model('DB')->resultset('domains')->create({
                domain => $resource->{domain}
            });
            my $provisioning_domain = $c->model('DB')->resultset('voip_domains')->create({
                domain => $resource->{domain}
            });
            my $reseller_id;
            if($c->user->roles eq "admin") {
                $reseller_id = $resource->{reseller_id};
            } elsif($c->user->roles eq "reseller") {
                $reseller_id = $c->user->reseller_id;
            }
            $billing_domain->create_related('domain_resellers', {
                reseller_id => $reseller_id,
            });
        } catch($e) {
            $c->log->error("failed to create domain: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create domain.");
            last;
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_domain = $self->item_by_id($c, $billing_domain->id);
            return $self->hal_from_item($c,$_domain); });

        $guard->commit;

        try {
            $self->xmpp_domain_reload($c, $resource->{domain}) if $xmpp_reload;
            NGCP::Panel::Utils::XMLDispatcher::sip_domain_reload($c, $resource->{domain}) if ($sip_reload);
        } catch($e) {
            $c->log->error("failed to activate domain: $e. Domain created"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to activate domain. Domain was created");
            $c->response->header(Location => sprintf('/%s%d', $c->request->path, $billing_domain->id));
            last;
        }

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $billing_domain->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
