package NGCP::Panel::Role::API::ManagerSecretary;
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
use Readonly;
use Data::Dumper;

Readonly my $dset_name => 'ms_autoset';

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::get("NGCP::Panel::Form::ManagerSecretaryAPI", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my $type = "managersecretary";

    my $prov_sub = $item->provisioning_voip_subscriber;
    die "no provisioning_voip_subscriber" unless $prov_sub;

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $item->uuid)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%s", $type, $item->uuid)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%s", $item->uuid)),
            $self->get_journal_relation_link($c, $item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $allowed_prefs = NGCP::Panel::Utils::Preferences::get_subscriber_allowed_prefs(
            c => $c,
            prov_subscriber => $prov_sub,
            pref_list => [qw/cfu cfb cft cfna cfs/],
    );

    my $resource = {};

    for my $item_cf ($prov_sub->voip_cf_mappings->all) {
        next unless $allowed_prefs->{$item_cf->type};
        my $dset = $item_cf->destination_set;
        next unless $dset->name eq $dset_name;
        next unless $dset->voip_cf_destinations->count;
        $resource = $self->_get_content($c, $item);
        last;
    }

    $form //= $self->get_form($c);
    $form->clear();
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        run => 0,
    );

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item) = @_;

    my $prov_sub = $item->provisioning_voip_subscriber;
    my $resource = {};

    for my $item_cf ($prov_sub->voip_cf_mappings->all) {
        my $dset = $item_cf->destination_set;
        next unless $dset->name eq $dset_name;
        next unless $dset->voip_cf_destinations->count;
        $resource = $self->_get_content($c, $item);
        last;
    }

    return unless %$resource;

    return $resource;
}

sub json_from_item {
    my ($self, $c, $item) = @_;

    my $resource = $self->resource_from_item($c, $item);

    return unless $resource;

    return JSON::to_json($resource);
}

sub _get_content {
    my ($self, $c, $item) = @_;
    my $prov_sub = $item->provisioning_voip_subscriber;
    my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, attribute => 'secretary_numbers', prov_subscriber => $prov_sub);
    my @secretary_numbers = ();
    if ($pref_rs) {
        map { push @secretary_numbers, { number => $_->value } } $pref_rs->all;
    }
    return { uuid => $prov_sub->uuid,
             secretary_numbers => [ @secretary_numbers ] };
}

sub _item_rs {
    my ($self, $c) = @_;

    my $filter = {};
    if ($c->request->method eq 'GET') {
        $filter = { 'destination_set.name' => $dset_name };
    }

    my $item_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        'me.status' => { '!=' => 'terminated' },
        %$filter
    },{
        'prefetch' => { 'provisioning_voip_subscriber' =>
                        { 'voip_cf_mappings' => 'destination_set' } },
    });

    if ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    } elsif ($c->user->roles eq 'subscriberadmin') {
        $item_rs = $item_rs->search({
            'contract.id' => $c->user->account_id,
        }, {
            join => 'contract',
        });
    } elsif ($c->user->roles eq 'subscriber') {
        $item_rs = $item_rs->search({
            'me.uuid' => $c->user->uuid,
        });
    }

    return $item_rs;
}

sub item_by_uuid {
    my ($self, $c, $id) = @_;
    return $self->item_rs($c)->search_rs({'me.uuid' => $id})->first;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form, $preference) = @_;

    unless ($item) {
        $self->error($c, HTTP_NOT_FOUND, "Unknown subscriber.");
        return;
    }

    my $prov_sub = $item->provisioning_voip_subscriber;
    die "need provisioning_voip_subscriber" unless $prov_sub;

    delete $resource->{id};

    my $cf_type = 'cfu';

    if (!$preference || $preference ne 'internal') {
        my $allowed_prefs = NGCP::Panel::Utils::Preferences::get_subscriber_allowed_prefs(
            c => $c,
            prov_subscriber => $prov_sub,
            pref_list => [qw/cfu cfb cft cfna cfs/],
        );
        return unless $allowed_prefs->{$cf_type};
        return unless $self->validate_form(
            c => $c,
            form => $form,
            resource => $resource,
            run => 1,
        );
    }

    try {
        my $enable = $c->request->method eq 'PUT';
        my $mapping = $c->model('DB')->resultset('voip_cf_mappings')->search_rs({
            subscriber_id => $prov_sub->id,
            type => $cf_type,
        });
        my $dset;
        my $mapping_count = $mapping->count;
        if ($mapping_count > 1) {
            foreach my $m ($mapping->all) {
                $m->delete;
            }
            return unless $enable;
        }
        if ($mapping_count == 1) {
            $mapping = $mapping->first;
            $dset = $mapping->destination_set;
        } elsif ($enable) {
            $mapping = $c->model('DB')->resultset('voip_cf_mappings')->create({
                subscriber_id => $prov_sub->id,
                type => $cf_type,
            });
            $mapping->discard_changes; # get our row
        }

        my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, prov_subscriber => $prov_sub, attribute => $cf_type);

        unless ($enable) {
            if ($dset && $dset->name eq $dset_name) {
                $dset->delete;
            }
            $cf_preference->delete if $cf_preference;
            return;
        }

        if ($cf_preference->first) {
            $cf_preference->first->update({ value => $mapping->id });
        } else {
            $cf_preference->create({ value => $mapping->id });
        }

        my $primary_nr_rs = $item->primary_number;
        my $number;
        if ($primary_nr_rs) {
            $number = $primary_nr_rs->cc . ($primary_nr_rs->ac //'') . $primary_nr_rs->sn;
        } else {
            $number = $item->uuid;
        }

        if (!$dset || $dset->name ne $dset_name) {
            $dset = $mapping->create_related('destination_set',
                { name => $dset_name, subscriber_id => $prov_sub->id });
            $mapping->update({ destination_set_id => $dset->id });
        }

        my $destination = NGCP::Panel::Utils::Subscriber::field_to_destination(
                    destination => 'managersecretary',
                    number => $number,
                    domain => '',
                    uri => '',
                    cf_type => $cf_type,
                    c => $c,
                    subscriber => $prov_sub
        );

        $dset->voip_cf_destinations->update_or_create({
            destination => $destination,
            priority => 1,
        });

        $dset->discard_changes if $dset; # update destinations
    } catch($e) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "CallForward '$cf_type' could not be updated.", $e);
        return;
    }

    $item->discard_changes;
    return $item;
}

1;
# vim: set tabstop=4 expandtab:
