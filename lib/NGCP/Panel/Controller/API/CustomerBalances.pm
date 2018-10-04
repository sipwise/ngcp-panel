package NGCP::Panel::Controller::API::CustomerBalances;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ProfilePackages qw();

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines customer balances to access cash and free-time balance.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for customer balances belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contact.reseller_id' => $q };
                },
                second => sub {
                    { join => 'contact' };
                },
            },
        },
        {
            param => 'contact_id',
            description => 'Filter for contracts with a specific contact id',
            query => {
                first => sub {
                    my $q = shift;
                    { contact_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'status',
            description => 'Filter for contracts with a specific status (except "terminated")',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.status' => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'external_id',
            description => 'Filter for contracts with a specific external id',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.external_id' => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'domain',
            description => 'Filter for contracts with subscribers belonging to a specific domain',
            query => {
                first => sub {
                    my $q = shift;
                    { 'domain.domain' => { '=' => $q } };
                },
                second => sub {
                    {
                        join => { voip_subscribers => 'domain' },
                        distinct => 1,
                    };
                },
            },
        },
        {
            param => 'prepaid',
            description => 'Filter for contracts with a prepaid billing profile',
            query => {
                first => sub {
                    my $q = shift;
                    { 'billing_profile.prepaid' => ($q ? 1 : 0) };
                },
                second => sub {
                    {
                        join => { actual_billing_profile => 'billing_profile' },
                    };
                },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CustomerBalances/;

sub resource_name{
    return 'customerbalances';
}

sub dispatch_path{
    return '/api/customerbalances/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerbalances';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $items_rs = $self->item_rs($c,0,$now);
        (my $total_count, $items_rs) = $self->paginate_order_collection($c, $items_rs);
        my $items = NGCP::Panel::Utils::ProfilePackages::lock_contracts(c => $c,
            rs => $items_rs,
            contract_id_field => 'id');
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item (@$items) {
            my $balance = $self->item_by_id($c, $item->id,$now);
            push @embedded, $self->hal_from_item($c, $balance, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
        }
        $self->delay_commit($c,$guard);
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
        my $response = HTTP::Response->new(HTTP_OK, undef,
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
