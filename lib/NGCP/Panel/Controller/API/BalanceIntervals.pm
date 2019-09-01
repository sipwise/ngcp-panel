package NGCP::Panel::Controller::API::BalanceIntervals;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::DateTime;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Histories of contracts\' cash balance intervals.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for actual balance intervals of customers belonging to a specific reseller',
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
                    { status => $q };
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
        },    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::BalanceIntervals/;

sub resource_name{
    return 'balanceintervals';
}

sub dispatch_path{
    return '/api/balanceintervals/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-balanceintervals';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $contracts_rs = $self->item_rs($c,0,$now);
        (my $total_count, $contracts_rs, my $contracts_rows) = $self->paginate_order_collection($c, $contracts_rs);
        my $contracts = NGCP::Panel::Utils::ProfilePackages::lock_contracts(c => $c,
            rs => $contracts_rs,
            contract_id_field => 'id');
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $contract (@$contracts) {
            my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                contract => $contract,
                now => $now);
            #sleep(5);
            my $hal = $self->hal_from_balance($c, $balance, $form, $now, 0); #we prefer item collection links pointing to the contract's collection instead of this root collection
            $hal->_forcearray(1);
            push @embedded, $hal;
            my $link = Data::HAL::Link->new(relation => 'ngcp:'.$self->resource_name, href     => sprintf('/%s%d/%d', $c->request->path, $contract->id, $balance->id));
            $link->_forcearray(1);
            push @links, $link;
            #push @links, Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/%d/", $self->resource_name, $contract->id));
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
