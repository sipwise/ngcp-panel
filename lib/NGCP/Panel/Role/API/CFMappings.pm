package NGCP::Panel::Role::API::CFMappings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Form;
use NGCP::Panel::Utils::CallForwards qw();
use NGCP::Panel::Role::API::CFDestinationSets qw();
use NGCP::Panel::Role::API::CFTimeSets qw();
use NGCP::Panel::Role::API::CFSourceSets qw();
use NGCP::Panel::Role::API::CFBNumberSets qw();

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFMappingsAPI", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $type, $params) = @_;
    my $form;
    $params //= {};

    my $resource = { subscriber_id => $item->id, cfu => [], cfb => [], cfna => [], cft => [], cfs => [], cfr => [], cfo => []};
    my $b_subs_id = $item->id;
    my $prov_subscriber = $item->provisioning_voip_subscriber;
    my $p_subs_id = $prov_subscriber->id;

    my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'ringtimeout', prov_subscriber => $prov_subscriber)->first;
    $ringtimeout_preference = $ringtimeout_preference ? $ringtimeout_preference->value : undef;

    unless ($params->{skip_existing}) {
        my $mappings = $prov_subscriber->voip_cf_mappings->search(undef,
                {
                    prefetch => [
                        {destination_set => 'voip_cf_destinations'},
                        {time_set        => 'voip_cf_periods'},
                        {source_set      => 'voip_cf_sources'},
                        {bnumber_set     => 'voip_cf_bnumbers'}
                    ]
                }
            );
        for my $mapping ($mappings->all) {
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
                    ( enabled => $mapping->enabled ),
                    ( cfm_id => $mapping->id ),
                };
        }
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

    $self->expand_fields($c, $resource);
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
    if ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
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
    my ($self, $c, $item, $old_resource, $resource, $form, $params) = @_;
    
    return NGCP::Panel::Utils::CallForwards::update_cf_mappings(
        c => $c,
        resource => $resource,
        item => $item,
        err_code => sub {
            my ($err) = @_;
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        },
        validate_mapping_code => sub {
            my $res = shift;
            return $self->validate_form(
                c => $c,
                form => $form,
                resource => $res,
            );
        },
        validate_destination_set_code => sub {
            my $res = shift;
            return $self->validate_form(
                c => $c,
                form => NGCP::Panel::Role::API::CFDestinationSets->get_form($c),
                resource => $res,
            );
        },
        validate_time_set_code => sub {
            my $res = shift;
            return $self->validate_form(
                c => $c,
                form => NGCP::Panel::Role::API::CFTimeSets->get_form($c),
                resource => $res,
            );
        },
        validate_source_set_code => sub {
            my $res = shift;
            return $self->validate_form(
                c => $c,
                form => NGCP::Panel::Role::API::CFSourceSets->get_form($c),
                resource => $res,
            );
        },
        validate_bnumber_set_code => sub {
            my $res = shift;
            return $self->validate_form(
                c => $c,
                form => NGCP::Panel::Role::API::CFBNumberSets->get_form($c),
                resource => $res,
            );
        },
        params => $params,
    );

}

1;
