package NGCP::Panel::Controller::API::SubscriberPreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use JSON qw();
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ProfilePackages qw();
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD I_GET I_HEAD I_OPTIONS I_PATCH I_PUT /];
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

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::Preferences/;

sub resource_name{
    return 'subscriberpreferences';
}
sub dispatch_path{
    return '/api/subscriberpreferences/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscriberpreferences';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin subscriber/],
            Args => ($_ =~ m!^I_!) ? 1 : 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => ($_ =~ s!^I_!!r),
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
);

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

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
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $subscribers_rs = $self->item_rs($c, "subscribers");
        (my $total_count, $subscribers_rs) = $self->paginate_order_collection($c, $subscribers_rs);
        my $subscribers = NGCP::Panel::Utils::ProfilePackages::lock_contracts(c => $c,
            rs => $subscribers_rs,
            contract_id_field => 'contract_id');          
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my (@embedded, @links, %contract_map);
        for my $subscriber (@$subscribers) {
            next unless($subscriber->provisioning_voip_subscriber);
            my $contract = $subscriber->contract;
            my $balance; $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                contract => $contract,
                now => $now) if !exists $contract_map{$contract->id}; #apply underrun lock level
            $contract_map{$contract->id} = 1;
            push @embedded, $self->hal_from_item($c, $subscriber, "subscribers");
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $subscriber->id),
            );
        }
        $self->delay_commit($c,$guard);
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s', $self->dispatch_path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'prev', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page - 1, $rows));
        }

        my $hal = NGCP::Panel::Utils::DataHal->new(
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
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub I_GET :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        last unless $self->valid_id($c, $id);
        my $subscriber = $self->item_by_id($c, $id, "subscribers");
        last unless $self->resource_exists($c, subscriberpreference => $subscriber);

        my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                contract => $subscriber->contract,
            ); #apply underrun lock level
        my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
        $guard->commit; #potential db write ops in hal_from

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r
                =~ s/rel=self/rel="item self"/r;
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub I_HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub I_OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub I_PATCH :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');    
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
            ops => [qw/add replace remove copy/],
        );
        last unless $json;

        my $subscriber = $self->item_by_id($c, $id, "subscribers");
        last unless $self->resource_exists($c, subscriberpreferences => $subscriber);
        my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                contract => $subscriber->contract,
            ); #apply underrun lock level
        
        my $old_resource = $self->get_resource($c, $subscriber, "subscribers");
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        # last param is "no replace" to NOT delete existing prefs
        # for proper PATCH behavior
        $subscriber = $self->update_item($c, $subscriber, $old_resource, $resource, 0, "subscribers");
        last unless $subscriber;
        
        my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit; 

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub I_PUT :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');        
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $subscriber = $self->item_by_id($c, $id, "subscribers");
        last unless $self->resource_exists($c, systemcontact => $subscriber);
        my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                contract => $subscriber->contract,
            ); #apply underrun lock level        
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = $self->get_resource($c, $subscriber, "subscribers");

        # last param is "replace" to delete all existing prefs
        # for proper PUT behavior
        $subscriber = $self->update_item($c, $subscriber, $old_resource, $resource, 1, "subscribers");
        last unless $subscriber;

        my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit; 

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return;
}

1;

# vim: set tabstop=4 expandtab:
