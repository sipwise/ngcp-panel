package NGCP::Panel::Controller::API::BillingNetworks;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::BillingNetworks qw();
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'A Billing Network is a container for a number of network ranges.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'ip',
            description => 'Filter for billing networks containing a specific IP address',
            query => {
                first => sub {
                    my $q = shift;
                    my ($bytes,$version) = NGCP::Panel::Utils::BillingNetworks::ip_to_bytes($q);
                    return {} unless defined $bytes;
                    return {
                        'billing_network_blocks._ipv4_net_from' => { '<=', $bytes },
                        'billing_network_blocks._ipv4_net_to'  => { '>=', $bytes },
                    } if $version == 4;
                    return {
                        'billing_network_blocks._ipv6_net_from' => { '<=', $bytes },
                        'billing_network_blocks._ipv6_net_to'  => { '>=', $bytes },
                    } if $version == 6;
                },
                second => sub {
                    return { join => 'billing_network_blocks',
                             distinct => 1 }; #not neccessary if _CHECK_BLOCK_OVERLAPS was always on
                },
            },
        },
        {
            param => 'name',
            description => 'Filter for billing networks matching a name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
    ]},
);


with 'NGCP::Panel::Role::API::BillingNetworks';

class_has('resource_name', is => 'ro', default => 'billingnetworks');
class_has('dispatch_path', is => 'ro', default => '/api/billingnetworks/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-billingnetworks');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    return 1;
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $bns = $self->item_rs($c);

        (my $total_count, $bns) = $self->paginate_order_collection($c, $bns);
        my (@embedded, @links);
        for my $bn ($bns->all) {
            push @embedded, $self->hal_from_item($c, $bn, "billingnetworks");
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $bn->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/');
            #Data::HAL::Link->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s', $self->dispatch_path, $page, $rows));

        push @links, $self->collection_nav_links($page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $response = HTTP::Response->new(HTTP_OK, undef, 
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
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
        my $schema = $c->model('DB');
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }

        my $form = $self->get_form($c);
        $resource->{reseller_id} //= undef;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            exceptions => [ "reseller_id" ],
        );
        
        last unless $self->prepare_blocks_resource($c,$resource);
        my $blocks = delete $resource->{blocks};
        
        my $bn;
        try {
            $bn = $schema->resultset('billing_networks')->create($resource);
                #{
                #    name => $resource->{name},
                #    description => $resource->{description},
                #    reseller_id => $resource->{reseller_id},
                #}); #->discard_changes;
            for my $block (@$blocks) {
                $bn->create_related("billing_network_blocks", $block);
            }
        } catch($e) {
            $c->log->error("failed to create billingnetwork: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create billingnetwork.");
            return;
        };
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_bn = $self->item_by_id($c, $bn->id);
            return $self->hal_from_item($c, $_bn, "billingnetworks"); });
        
        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $bn->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

# vim: set tabstop=4 expandtab:
