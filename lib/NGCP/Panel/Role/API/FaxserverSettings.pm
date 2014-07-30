package NGCP::Panel::Role::API::FaxserverSettings;
use Moose::Role;
use Sipwise::Base;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::Faxserver::API;
use NGCP::Panel::Utils::Subscriber;

sub get_form {
    my ($self, $c, $type) = @_;

    return NGCP::Panel::Form::Faxserver::API->new(ctx => $c);
}

sub hal_from_item {
    my ($self, $c, $item) = @_;
    my $form;
    my $rwr_form = $self->get_form($c);
    my $type = 'faxserversettings';
    
    my $prov_subs = $item->provisioning_voip_subscriber;

    die "no provisioning_voip_subscriber" unless $prov_subs;

    my $fax_preference = $prov_subs->voip_fax_preference;
    unless ($fax_preference) {
        try {
            $fax_preference = $prov_subs->create_related('voip_fax_preference', {});
            $fax_preference->discard_changes; # reload
        } catch($e) {
            $c->log->error("Error creating empty fax_preference on get");
        };
    }

    my %resource = (
            $fax_preference ? $fax_preference->get_inflated_columns : (),
            subscriber_id => $item->id,
        );
    delete $resource{id};
    my @destinations;
    for my $dest ($prov_subs->voip_fax_destinations->all) {
        push @destinations, {$dest->get_inflated_columns};
    }
    $resource{destinations} = \@destinations;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%s", $type, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );
   

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $hal->resource(\%resource);
    return $hal;
}

sub item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search(
            { 'me.status' => { '!=' => 'terminated' } },
            { prefetch => 'provisioning_voip_subscriber',},
        );
    if($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    return $self->item_rs($c)->search_rs({'me.id' => $id})->first;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $billing_subscriber_id = $item->id;
    my $prov_subs = $item->provisioning_voip_subscriber;
    die "need provisioning_voip_subscriber" unless $prov_subs;
    my $prov_subscriber_id = $prov_subs->id;
    my $destinations_rs = $prov_subs->voip_fax_destinations;

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        run => 1,
    );

    if (! exists $resource->{destinations} ) {
        $resource->{destinations} = [];
    }
    if (ref $resource->{destinations} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'destinations'. Must be an array.");
        return;
    }

    my %update_fields = %{ $resource };
    delete $update_fields{destinations};

    try {
        $prov_subs->delete_related('voip_fax_preference');
        $destinations_rs->delete;
        $prov_subs->create_related('voip_fax_preference', \%update_fields);
        $prov_subs->discard_changes; #reload

        for my $dest (@{ $resource->{destinations} }) {
            $destinations_rs->create($dest);
        }
    } catch($e) {
        $c->log->error("Error Updating faxserversettings: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "faxserversettings could not be updated.");
        return;
    };

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
