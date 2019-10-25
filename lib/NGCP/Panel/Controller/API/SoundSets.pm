package NGCP::Panel::Controller::API::SoundSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines sound sets for both system and customers.';
};

sub query_params {
    return [
        {
            param => 'customer_id',
            description => 'Filter for sound sets of a specific customer',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'contract_id' => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for sound sets of a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'reseller_id' => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'name',
            description => 'Filter for sound sets with a specific name (wildcard pattern allowed)',
            query => {
                first => sub {
                    my $q = shift;
                    return { name => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::SoundSets/;

sub resource_name{
    return 'soundsets';
}
sub dispatch_path{
    return '/api/soundsets/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-soundsets';
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
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item ($items->all) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
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
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

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

        $resource->{contract_id} = delete $resource->{customer_id};
        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        #$form //= $self->get_form($c);
        #return unless $self->validate_form(
        #    c => $c,
        #    form => $form,
        #    resource => $resource,
        #);

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }
        my $reseller = $c->model('DB')->resultset('resellers')->find({
            id => $resource->{reseller_id},
        });
        unless($reseller) {
            $c->log->error("invalid reseller_id '$$resource{reseller_id}'"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Reseller does not exist");
            return;
        }
        my $customer;
        if(defined $resource->{contract_id}) {
            $customer = $c->model('DB')->resultset('contracts')->find({
                id => $resource->{contract_id},
                'contact.reseller_id' => { '!=' => undef },
            },{
                join => 'contact',
            });
            unless($customer) {
                $c->log->error("invalid customer_id '$$resource{contract_id}'"); # TODO: user, message, trace, ...
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Customer does not exist");
                return;
            }
            unless($customer->contact->reseller_id == $reseller->id) {
                $c->log->error("customer_id '$$resource{contract_id}' doesn't belong to reseller_id '$$resource{reseller_id}"); # TODO: user, message, trace, ...
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller for customer");
                return;
            }
        }
        $resource->{contract_default} //= 0;

        my $item;
        try {
            $item = $c->model('DB')->resultset('voip_sound_sets')->create($resource);
            if($item->contract_id && $item->contract_default) {
                $c->model('DB')->resultset('voip_sound_sets')->search({
                    reseller_id => $item->reseller_id,
                    contract_id => $item->contract_id,
                    contract_default => 1,
                    id => { '!=' => $item->id },
                })->update({ contract_default => 0 });
            }

        } catch($e) {
            $c->log->error("failed to create soundset: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create soundset.");
            last;
        }
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_item = $self->item_by_id($c, $item->id); #reload is required here, otherwise description field is missing
            return $self->hal_from_item($c, $_item); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
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