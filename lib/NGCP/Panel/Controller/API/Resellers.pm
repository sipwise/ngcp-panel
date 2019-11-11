package NGCP::Panel::Controller::API::Resellers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use JSON qw();
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Reseller;
use NGCP::Panel::Utils::Rtc;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a reseller on the system. A reseller can manage his own <a href="#domains">Domains</a> and <a href="#customers">Customers</a>.';
}

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for resellers matching the given name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Resellers/;

sub resource_name{
    return 'resellers';
}

sub dispatch_path{
    return '/api/resellers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-resellers';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $resellers = $self->item_rs($c);
        (my $total_count, $resellers, my $resellers_rows) = $self->paginate_order_collection($c, $resellers);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $reseller (@$resellers_rows) {
            push @embedded, $self->hal_from_reseller($c, $reseller, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $reseller->id),
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
        my $schema = $c->model('DB');
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        $resource->{contract_id} //= undef;
        if(defined $resource->{contract_id} && !is_int($resource->{contract_id})) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contract_id', not a number");
            return;
        }
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        if($schema->resultset('resellers')->find({
                contract_id => $resource->{contract_id},
        })) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contract_id', reseller with this contract already exists");
            last;
        }
        if($schema->resultset('resellers')->search({
                name => $resource->{name},
                status => 'active'
        })->first) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'name', reseller with this name already exists");
            last;
        }
        my $contract = $schema->resultset('contracts')->find($resource->{contract_id});
        unless($contract) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contract_id'.");
            last;
        }
        if($contract->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contract_id' linking to a customer contact");
            last;
        }

        my $reseller;
        try {
            $reseller = $schema->resultset('resellers')->update_or_create(
                {
                    name => $resource->{name},
                    status => $resource->{status},
                    contract_id => $resource->{contract_id},
                },
                {
                    key => 'name_idx'
                }
            );
            NGCP::Panel::Utils::Reseller::create_email_templates( c => $c, reseller => $reseller );
            NGCP::Panel::Utils::Rtc::modify_reseller_rtc(
                resource => $resource,
                config => $c->config,
                reseller_item => $reseller,
                err_code => sub {
                    my ($msg, $debug) = @_;
                    $c->log->debug($debug) if $debug;
                    $c->log->warn($msg);
                    die "failed to create rtcengine reseller";
                });
        } catch($e) {
            $c->log->error("failed to create reseller: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create reseller.");
            last;
        }
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_reseller = $self->reseller_by_id($c, $reseller->id);
            return $self->hal_from_reseller($c, $_reseller, $form); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $reseller->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
