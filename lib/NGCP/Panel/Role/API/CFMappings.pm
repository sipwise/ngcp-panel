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

    $params //= {};

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
    my $domain = $item->provisioning_voip_subscriber->domain->domain // '';
    my $primary_nr_rs = $item->primary_number;
    my $number;
    if ($primary_nr_rs) {
        $number = $primary_nr_rs->cc . ($primary_nr_rs->ac //'') . $primary_nr_rs->sn;
    } else {
        $number = $item->uuid;
    }
    my @new_mappings;
    my @new_destinations;
    my @new_times;
    my @new_sources;
    my @new_bnumbers;
    my @new_dsets;
    my @new_tsets;
    my @new_ssets;
    my @new_bsets;
    my %cf_preferences;
    my $dsets_rs = $c->model('DB')->resultset('voip_cf_destination_sets');
    my $tsets_rs = $c->model('DB')->resultset('voip_cf_time_sets');
    my $ssets_rs = $c->model('DB')->resultset('voip_cf_source_sets');
    my $bsets_rs = $c->model('DB')->resultset('voip_cf_bnumber_sets');
    my $dset_max_id = $dsets_rs->search( undef, { for => 'update' } )->get_column('id')->max() // -1;
    my $tset_max_id = $tsets_rs->search( undef, { for => 'update' } )->get_column('id')->max() // -1;
    my $sset_max_id = $ssets_rs->search( undef, { for => 'update' } )->get_column('id')->max() // -1;
    my $bset_max_id = $bsets_rs->search( undef, { for => 'update' } )->get_column('id')->max() // -1;

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
            } elsif ($mapping->{destinationset} && !ref $mapping->{destinationset}) {
                $dset = $dsets_rs->find({
                    subscriber_id => $p_subs_id,
                    name => $mapping->{destinationset},
                });
            } elsif ($mapping->{destinationset} && ref $mapping->{destinationset} eq 'HASH') {
                $mapping->{destinationset}->{subscriber_id} = $p_subs_id;
                $form = NGCP::Panel::Role::API::CFDestinationSets->get_form($c);
                return unless $self->validate_form(
                    c => $c,
                    resource => $mapping->{destinationset},
                    form => $form,
                );
                if (! exists $mapping->{destinationset}->{destinations} ) {
                    $mapping->{destinationset}->{destinations} = [];
                }
                if (!NGCP::Panel::Role::API::CFDestinationSets->check_destinations($c, $mapping->{destinationset})) {
                    return;
                }

                $dset_max_id +=2;
                $dset = {
                    id => $dset_max_id,
                    name => $mapping->{destinationset}->{name},
                    subscriber_id => $p_subs_id,
                };
                push @new_dsets, $dset;
                for my $d ( @{$mapping->{destinationset}->{destinations}} ) {
                    delete $d->{destination_set_id};
                    delete $d->{simple_destination};
                    $d->{destination} = NGCP::Panel::Utils::Subscriber::field_to_destination(
                            destination => $d->{destination},
                            number => $number,
                            domain => $domain,
                            uri => $d->{destination},
                        );
                    $d->{destination_set_id} = $dset_max_id;
                    push @new_destinations, $d;
                }
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
            } elsif (defined $mapping->{timeset} && !ref $mapping->{timeset}) {
                $tset = $tsets_rs->find({
                    subscriber_id => $p_subs_id,
                    name => $mapping->{timeset},
                });
                $has_tset = 1;
            } elsif ($mapping->{timeset} && ref $mapping->{timeset} eq 'HASH') {
                $mapping->{timeset}->{subscriber_id} = $p_subs_id;
                $form = NGCP::Panel::Role::API::CFTimeSets->get_form($c);
                return unless $self->validate_form(
                    c => $c,
                    resource => $mapping->{timeset},
                    form => $form,
                );
                if (! exists $mapping->{timeset}->{times} ) {
                    $mapping->{timeset}->{times} = [];
                }
                if (ref $mapping->{timeset}->{times} ne "ARRAY") {
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'times'. Must be an array.");
                    return;
                }
                $tset_max_id +=2;
                $tset = {
                    id => $tset_max_id,
                    name => $mapping->{timeset}->{name},
                    subscriber_id => $p_subs_id,
                };
                push @new_tsets, $tset;
                for my $t ( @{$mapping->{timeset}->{times}} ) {
                    delete $t->{time_set_id};
                    $t->{time_set_id} = $tset_max_id;
                    push @new_times, $t;
                }
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
            } elsif (defined $mapping->{sourceset} && !ref $mapping->{sourceset}) {
                $sset = $ssets_rs->find({
                    subscriber_id => $p_subs_id,
                    name => $mapping->{sourceset},
                });
                $has_sset = 1;
            } elsif ($mapping->{sourceset} && ref $mapping->{sourceset} eq 'HASH') {
                $mapping->{sourceset}->{subscriber_id} = $p_subs_id;
                $form = NGCP::Panel::Role::API::CFSourceSets->get_form($c);
                return unless $self->validate_form(
                    c => $c,
                    resource => $mapping->{sourceset},
                    form => $form,
                );
                if (! exists $mapping->{sourceset}->{sources} ) {
                    $mapping->{sourceset}->{sources} = [];
                }
                if (ref $mapping->{sourceset}->{sources} ne "ARRAY") {
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'sources'. Must be an array.");
                    return;
                }

                $sset_max_id +=2;
                $sset = {
                    id => $sset_max_id,
                    name => $mapping->{sourceset}->{name},
                    mode => $mapping->{sourceset}->{mode},
                    is_regex => $mapping->{sourceset}->{is_regex} // 0,
                    subscriber_id => $p_subs_id,
                };
                push @new_ssets, $sset;
                for my $s ( @{$mapping->{sourceset}->{sources}} ) {
                    push @new_sources, {
                        source_set_id => $sset_max_id,
                        source => $s->{source},
                    };
                }
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
            } elsif (defined $mapping->{bnumberset} && !ref $mapping->{bnumberset}) {
                $bset = $bsets_rs->find({
                    subscriber_id => $p_subs_id,
                    name => $mapping->{bnumberset},
                });
                $has_bset = 1;
            } elsif ($mapping->{bnumberset} && ref $mapping->{bnumberset} eq 'HASH') {
                $mapping->{bnumberset}->{subscriber_id} = $p_subs_id;
                $form = NGCP::Panel::Role::API::CFBNumberSets->get_form($c);
                return unless $self->validate_form(
                    c => $c,
                    resource => $mapping->{bnumberset},
                    form => $form,
                );
                if (! exists $mapping->{bnumberset}->{bnumbers} ) {
                    $mapping->{bnumberset}->{bnumbers} = [];
                }
                if (ref $mapping->{bnumberset}->{bnumbers} ne "ARRAY") {
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'bnumbers'. Must be an array.");
                    return;
                }

                $bset_max_id +=2;
                $bset = {
                    id => $bset_max_id,
                    name => $mapping->{bnumberset}->{name},
                    mode => $mapping->{bnumberset}->{mode},
                    is_regex => $mapping->{bnumberset}->{is_regex} // 0,
                    subscriber_id => $p_subs_id,
                };
                push @new_bsets, $bset;
                for my $b ( @{$mapping->{bnumberset}->{bnumbers}} ) {
                    push @new_bnumbers, {
                        bnumber_set_id => $bset_max_id,
                        bnumber => $b->{bnumber},
                    };
                }
            }
            if($has_bset && !$bset) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'bnumberset'. Could not be found.");
                return;
            }
            push @new_mappings, {
                    destination_set_id => ref $dset eq 'HASH' ? $dset->{id} : $dset->id,
                    time_set_id => ref $tset eq 'HASH' ? $tset->{id} : ( $tset ? $tset->id : undef ),
                    source_set_id => ref $sset eq 'HASH' ? $sset->{id} : ( $sset ? $sset->id : undef ),
                    bnumber_set_id => ref $bset eq 'HASH' ? $bset->{id} : ( $bset ? $bset->id : undef ),
                    type => $type,
                    enabled => defined $mapping->{enabled} ? $mapping->{enabled} : 1,
                };
        }
    }

    try {
        my $autoattendant_count = 0;
        $c->model('DB')->resultset('voip_cf_destination_sets')->populate(\@new_dsets);
        $c->model('DB')->resultset('voip_cf_time_sets')->populate(\@new_tsets);
        $c->model('DB')->resultset('voip_cf_source_sets')->populate(\@new_ssets);
        $c->model('DB')->resultset('voip_cf_bnumber_sets')->populate(\@new_bsets);
        $c->model('DB')->resultset('voip_cf_destinations')->populate(\@new_destinations);
        $c->model('DB')->resultset('voip_cf_periods')->populate(\@new_times);
        $c->model('DB')->resultset('voip_cf_sources')->populate(\@new_sources);
        $c->model('DB')->resultset('voip_cf_bnumbers')->populate(\@new_bnumbers);

        unless ($params->{add_only}) {
            foreach my $map($mappings_rs->all) {
                $autoattendant_count += NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($map->destination_set);
            }
            $mappings_rs->delete;
            for my $type ( qw/cfu cfb cft cfna cfs cfr cfo/) {
                $cf_preferences{$type}->delete;
            }
        }

        $mappings_rs->populate(\@new_mappings);
        for my $type ( qw/cfu cfb cft cfna cfs cfr cfo/) {
            my @mapping_ids_by_type = $mappings_rs->search(
                {
                    type => $type
                },
                {
                    select => [qw/me.id /],
                    as => [qw/value/],
                    result_class => 'DBIx::Class::ResultClass::HashRefInflator'
                }
            )->all();
            $cf_preferences{$type}->populate(\@mapping_ids_by_type);
        }

        unless ($params->{add_only}) {
            for my $mapping ($mappings_rs->all) {
                $autoattendant_count -= NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($mapping->destination_set);
            }
        } else {
            for my $d (@new_destinations) {
                $autoattendant_count -= (NGCP::Panel::Utils::Subscriber::destination_to_field($d->{destination}))[0] eq 'autoattendant' ? 1 : 0;
            }
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
        } elsif ($c->model('DB')->resultset('voip_cf_mappings')->search_rs({
                subscriber_id => $item->provisioning_voip_subscriber->id,
                type => 'cft',
                enabled => 1,
            })->count == 0) {
            NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c,
                attribute => 'ringtimeout',
                prov_subscriber => $item->provisioning_voip_subscriber)->delete;
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
