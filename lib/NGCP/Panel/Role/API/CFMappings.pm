package NGCP::Panel::Role::API::CFMappings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Form;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFMappingsAPI", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my $resource = { subscriber_id => $item->id, cfu => [], cfb => [], cfna => [], cft => [], cfs => [], cfr => [], cfo => []};
    my $b_subs_id = $item->id;
    my $p_subs_id = $item->provisioning_voip_subscriber->id;

    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'ringtimeout', prov_subscriber => $item->provisioning_voip_subscriber)->first;
    $ringtimeout_preference = $ringtimeout_preference ? $ringtimeout_preference->value : undef;

    for my $mapping ($item->provisioning_voip_subscriber->voip_cf_mappings->all) {
        push @{ $resource->{$mapping->type} }, {
                $mapping->destination_set ? (
                    destinationset => $mapping->destination_set->name,
                    destinationset_id => $mapping->destination_set->id,
                ) : (
                    destinationset => undef,
                    destinationset_id => undef,
                ),
                $mapping->time_set ? (
                    timeset => $mapping->time_set->name,
                    timeset_id => $mapping->time_set->id,
                ) : (
                    timeset => undef,
                    timeset_id => undef,
                ),
                $mapping->source_set ? (
                    sourceset => $mapping->source_set->name,
                    sourceset_id => $mapping->source_set->id,
                ) : (
                    sourceset => undef,
                    sourceset_id => undef,
                ),
                $mapping->bnumber_set ? (
                    bnumberset => $mapping->bnumber_set->name,
                    bnumberset_id => $mapping->bnumber_set->id,
                ) : (
                    bnumberset => undef,
                    bnumberset_id => undef,
                ),
            };
    }

    my $adm = $c->user->roles eq "admin" || $c->user->roles eq "reseller";

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
            Data::HAL::Link->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $b_subs_id)),
            $adm ? $self->get_journal_relation_link($c, $item->id) : (),
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
    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub _item_rs {
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
    } elsif($c->user->roles eq "subscriber" || $c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'me.uuid' => $c->user->uuid,
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
    my $ssets_rs = $c->model('DB')->resultset('voip_cf_source_sets');
    my $bsets_rs = $c->model('DB')->resultset('voip_cf_bnumber_sets');

    for my $type ( qw/cfu cfb cft cfna cfs cfr cfo/) {
        if (ref $resource->{$type} ne "ARRAY") {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field '$type'. Must be an array.");
            return;
        }

        $cf_preferences{$type} = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, prov_subscriber => $item->provisioning_voip_subscriber, attribute => $type);
        for my $mapping (@{ $resource->{$type} }) {
            my $dset;
            if(defined $mapping->{destinationset_id}) {
                $dset = $dsets_rs->find({
                    subscriber_id => $p_subs_id,
                    id => $mapping->{destinationset_id},
                });
            } elsif($mapping->{destinationset}) {
                $dset = $dsets_rs->find({
                    subscriber_id => $p_subs_id,
                    name => $mapping->{destinationset},
                });
            } else {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing field 'destinationset' or 'destinationset_id' in '$type'.");
                return;
            }
            unless ($dset) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'destinationset'. Could not be found.");
                return;
            }

            my $tset; my $has_tset;
            if (defined $mapping->{timeset_id}) {
                $tset = $tsets_rs->find({
                    subscriber_id => $p_subs_id,
                    id => $mapping->{timeset_id},
                });
                $has_tset = 1;
            } elsif (defined $mapping->{timeset}) {
                $tset = $tsets_rs->find({
                    subscriber_id => $p_subs_id,
                    name => $mapping->{timeset},
                });
                $has_tset = 1;
            }
            if($has_tset && !$tset) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'timeset'. Could not be found.");
                return;
            }

            my $sset; my $has_sset;
            if (defined $mapping->{sourceset_id}) {
                $sset = $ssets_rs->find({
                    subscriber_id => $p_subs_id,
                    id => $mapping->{sourceset_id},
                });
                $has_sset = 1;
            } elsif (defined $mapping->{sourceset}) {
                $sset = $ssets_rs->find({
                    subscriber_id => $p_subs_id,
                    name => $mapping->{sourceset},
                });
                $has_sset = 1;
            }
            if($has_sset && !$sset) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'sourceset'. Could not be found.");
                return;
            }

            my $bset; my $has_bset;
            if (defined $mapping->{bnumberset_id}) {
                $bset = $bsets_rs->find({
                    subscriber_id => $p_subs_id,
                    id => $mapping->{bnumberset_id},
                });
                $has_bset = 1;
            } elsif (defined $mapping->{bnumberset}) {
                $bset = $bsets_rs->find({
                    subscriber_id => $p_subs_id,
                    name => $mapping->{bnumberset},
                });
                $has_bset = 1;
            }
            if($has_bset && !$bset) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'bnumberset'. Could not be found.");
                return;
            }

            push @new_mappings, $mappings_rs->new_result({
                    destination_set_id => $dset->id,
                    time_set_id => $tset ? $tset->id : undef,
                    source_set_id => $sset ? $sset->id : undef,
                    bnumber_set_id => $bset ? $bset->id : undef,
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
        for my $type ( qw/cfu cfb cft cfna cfs cfr cfo/) {
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
                    c => $c, schema => $c->model('DB'),
                    subscriber_id => $item->id,
                    type => 'end_ivr',
                );
            }
        } elsif ($autoattendant_count < 0) {
            while ($autoattendant_count != 0) {
                $autoattendant_count++;
                NGCP::Panel::Utils::Events::insert(
                    c => $c, schema => $c->model('DB'),
                    subscriber_id => $item->id,
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
