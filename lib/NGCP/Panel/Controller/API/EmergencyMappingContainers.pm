package NGCP::Panel::Controller::API::EmergencyMappingContainers;
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
    return 'Defines a container which holds a collection of <a href="#emergencymappings">Emergency Mappings</a>.';
};

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for emergency mapping containers with a specific name (wildcards possible)',
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for emergency mapping containers for a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::EmergencyMappingContainers/;

sub resource_name{
    return 'emergencymappingcontainers';
}

sub dispatch_path{
    return '/api/emergencymappingcontainers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-emergencymappingcontainers';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
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
        if($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }
        my $dup_item = $c->model('DB')->resultset('emergency_containers')->find({
            reseller_id => $resource->{reseller_id},
            name => $resource->{name},
        });
        if($dup_item) {
            $c->log->error("emergency mapping container with name '$$resource{name}' already exists for this reseller");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "emergency mapping container with this name already exists for this reseller");
            return;
        }

        my $item;
        try {
            $item = $schema->resultset('emergency_containers')->create($resource);
        } catch($e) {
            $c->log->error("failed to create emergency mapping container: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create emergency mapping container.");
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
