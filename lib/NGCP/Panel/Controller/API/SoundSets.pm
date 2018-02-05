package NGCP::Panel::Controller::API::SoundSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines sound sets for both system and customers.';  # should allow a different description per role
};

sub query_params {
    return [
        {
            param => 'customer_id',  # should allow different params per role (no security-problem)
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

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SoundSets/;

sub resource_name{
    return 'soundsets';
}

sub dispatch_path{
    return '/api/soundsets/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-soundsets';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

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

        if ($c->user->roles eq "admin") {
        } elsif ($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        } elsif ($c->user->roles eq "subscriberadmin") {
            $resource->{contract_id} = $c->user->account_id;
            $resource->{reseller_id} = $c->user->contract->contact->reseller_id;
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

1;

# vim: set tabstop=4 expandtab:
