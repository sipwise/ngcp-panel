package NGCP::Panel::Role::API::CFMappings;
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
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Form::CFMappingsAPI;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::CFMappingsAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my $resource = { subscriber_id => $item->id, cfu => [], cfb => [], cfna => [], cft => [], };
    my $b_subs_id = $item->id;
    my $p_subs_id = $item->provisioning_voip_subscriber->id;

    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'ringtimeout', prov_subscriber => $item->provisioning_voip_subscriber)->first;
    $ringtimeout_preference = $ringtimeout_preference ? $ringtimeout_preference->value : undef;

    for my $mapping ($item->provisioning_voip_subscriber->voip_cf_mappings->all) {
        my $dset = $mapping->destination_set ? $mapping->destination_set->name : undef;
        my $tset = $mapping->time_set ? $mapping->time_set->name : undef;
        push $resource->{$mapping->type}, {
                destinationset => $dset,
                timeset => $tset,
            };
    }

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%d", $type, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $b_subs_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        run => 0,
    );
    $resource->{cft_ringtimeout} = $ringtimeout_preference;
    $hal->resource($resource);
    return $hal;
}

sub item_rs {
    my ($self, $c, $type) = @_;
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

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    if (ref $resource ne "HASH") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Must be a hash.");
        return;
    }

    delete $resource->{id};
    my $schema = $c->model('DB');

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $mappings_rs = $item->provisioning_voip_subscriber->voip_cf_mappings;
    my $p_subs_id = $item->provisioning_voip_subscriber->id;
    my @new_mappings;
    my %cf_preferences;
    my $dsets_rs = $c->model('DB')->resultset('voip_cf_destination_sets');
    my $tsets_rs = $c->model('DB')->resultset('voip_cf_time_sets');

    for my $type ( qw/cfu cfb cft cfna/) {
        if (ref $resource->{$type} ne "ARRAY") {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field '$type'. Must be an array.");
            return;
        }

        $cf_preferences{$type} = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, prov_subscriber => $item->provisioning_voip_subscriber, attribute => $type);
        for my $mapping (@{ $resource->{$type} }) {
            unless ($mapping->{destinationset}) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'destinationset' in '$type'. Must be defined.");
                return;
            }
            my $dset = $dsets_rs->find({subscriber_id => $p_subs_id, name => $mapping->{destinationset}, });
            unless ($dset) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'destinationset'. Could not be found.");
                return;
            }
            my $tset;
            if ($mapping->{timeset}) {
                $tset = $tsets_rs->find({subscriber_id => $p_subs_id, name => $mapping->{timeset}, });
                unless ($tset) {
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'timeset'. Could not be found.");
                    return;
                }
            }
            push @new_mappings, $mappings_rs->new_result({
                    destination_set_id => $dset->id,
                    time_set_id => $tset ? $tset->id : undef,
                    type => $type,
                });
        }
    }

    try {
        my $autoattendant_count = 0;
        foreach my $map($mappings_rs->all) {
            $autoattendant_count += NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($map->destination_set);
        }
        $mappings_rs->delete;
        for my $type ( qw/cfu cfb cft cfna/) {
            $cf_preferences{$type}->delete;
        }
        for my $mapping ( @new_mappings ) {
            $mapping->insert;
            $cf_preferences{$mapping->type}->create({ value => $mapping->id });
            $autoattendant_count -= NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($mapping->destination_set);
        }

        if ($autoattendant_count > 0) {
            while ($autoattendant_count != 0) {
                $autoattendant_count--;
                NGCP::Panel::Utils::Events::insert(
                    schema => $c->model('DB'),
                    subscriber => $item,
                    type => 'end_ivr',
                );
            }
        } elsif ($autoattendant_count < 0) {
            while ($autoattendant_count != 0) {
                $autoattendant_count++;
                NGCP::Panel::Utils::Events::insert(
                    schema => $c->model('DB'),
                    subscriber => $item,
                    type => 'start_ivr',
                );
            }
        }

        if ($resource->{cft_ringtimeout} && $resource->{cft_ringtimeout} > 0) {
            my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'ringtimeout', prov_subscriber => $item->provisioning_voip_subscriber);

            if($ringtimeout_preference->first) {
                $ringtimeout_preference->first->update({
                    value => $resource->{cft_ringtimeout},
                });
            } else {
                $ringtimeout_preference->create({
                    value => $resource->{cft_ringtimeout},
                });
            }
        }

    } catch($e) {
        $c->log->error("failed to create cfmapping: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfmapping.");
        return;
    };

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
