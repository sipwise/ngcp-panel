package NGCP::Panel::Controller::API::LnpCarriers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Reseller qw();

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines an LNP carrier with its routing prefix and holds a collection of <a href="#lnpnumbers">LNP Numbers</a>.';
};

sub query_params {
    return [
        {
            param => 'prefix',
            description => 'Filter for LNP carriers with a specific prefix (wildcards possible)',
            query => {
                first => sub {
                    my $q = shift;
                    { prefix => { like =>  $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'name',
            description => 'Filter for LNP carriers with a specific name (wildcards possible)',
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

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::LnpCarriers/;

sub resource_name{
    return 'lnpcarriers';
}

sub dispatch_path{
    return '/api/lnpcarriers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-lnpcarriers';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});

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
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        my $dup_item = $c->model('DB')->resultset('lnp_providers')->find({
            name => $resource->{name},
        });
        if($dup_item) {
            $c->log->error("lnp carrier with name '$$resource{name}' already exists"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "LNP carrier with this name already exists");
            return;
        }

        my $item;
        try {
            $item = $schema->resultset('lnp_providers')->create($resource);
        } catch($e) {
            $c->log->error("failed to create lnp carrier: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create lnp carrier.");
            last;
        }
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_item = $self->item_by_id($c, $item->id);
            return $self->hal_from_item($c, $_item,$form); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
