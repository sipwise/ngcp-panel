package NGCP::Panel::Controller::API::SubscriberPreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use JSON qw();
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract qw();
use NGCP::Panel::Utils::ProfilePackages qw();

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub resource_name{
    return 'subscriberpreferences';
}

sub container_resource_type{
    return 'subscribers';
}

sub dispatch_path{
    return '/api/subscriberpreferences/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscriberpreferences';
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#subscribers">Subscriber</a>. The full list of properties can be obtained via <a href="/api/subscriberpreferencedefs/">SubscriberPreferenceDefs</a>.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for subscribers of customers belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contact.reseller_id' => $q };
                },
                second => sub {
                    { join => { 'contract' => 'contact' } };
                },
            },
        },
        {
            param => 'contact_id',
            description => 'Filter for subscribers of contracts with a specific contact id',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contract.contact_id' => $q };
                },
                second => sub {},
            },
        },
    ];
}

sub documentation_sample {
    return {
        block_in_mode  => JSON::true,
        block_in_list  => [ "1234" ],
        concurrent_max => 5,
        music_on_hold  => JSON::true,
        peer_auth_user => "mypeer",
    };
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    TX_START:
    $c->clear_errors;
    try {
        my $guard = $c->model('DB')->txn_scope_guard;
        {
            my $subscribers_rs = $self->item_rs($c, "subscribers");
            (my $total_count, $subscribers_rs, my $subscribers_rows) = $self->paginate_order_collection($c, $subscribers_rs);
            my $subscribers = NGCP::Panel::Utils::Contract::acquire_contract_rowlocks(
                c => $c,
                rs => $subscribers_rs,
                contract_id_field => 'contract_id',
                skip_locked => ($c->request->header('X-Delay-Commit') ? 0 : 1),
            );
            my $now = NGCP::Panel::Utils::DateTime::current_local;
            my (@embedded, @links, %contract_map);
            $self->expand_prepare_collection($c);
            for my $subscriber (@$subscribers) {
                next unless($subscriber->provisioning_voip_subscriber);
                my $contract = $subscriber->contract;
                my $balance; $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                    contract => $contract,
                    now => $now) if !exists $contract_map{$contract->id}; #apply underrun lock level
                $contract_map{$contract->id} = 1;
                push @embedded, $self->hal_from_item($c, $subscriber, "subscribers");
                push @links, Data::HAL::Link->new(
                    relation => 'ngcp:'.$self->resource_name,
                    href     => sprintf('%s%d', $self->dispatch_path, $subscriber->id),
                );
            }
            $self->expand_collection_fields($c, \@embedded);
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
    } catch($e) {
        if ($self->check_deadlock($c, $e)) {
            goto TX_START;
        }
        unless ($c->has_errors) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error', $e);
            last;
        }
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
