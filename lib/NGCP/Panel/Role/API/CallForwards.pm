package NGCP::Panel::Role::API::CallForwards;
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

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::get("NGCP::Panel::Form::CFSimpleAPI", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my $type = "callforwards";

    my $prov_subs = $item->provisioning_voip_subscriber;
    die "no provisioning_voip_subscriber" unless $prov_subs;

    my %resource = (subscriber_id => $prov_subs->id);

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
            $self->get_journal_relation_link($c, $item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $allowed_prefs = NGCP::Panel::Utils::Preferences::get_subscriber_allowed_prefs(
            c => $c,
            prov_subscriber => $prov_subs,
            pref_list => [qw/cfu cfb cft cfna cfs cfr cfo/],
        );
    @resource{qw/cfu cfb cft cfna cfs cfr cfo/} = ({}) x 5;
    for my $item_cf ($item->provisioning_voip_subscriber->voip_cf_mappings->all) {
        next unless ($allowed_prefs->{$item_cf->type});
        $resource{$item_cf->type} = $self->_contents_from_cfm($c, $item_cf, $item);
    }
    if(keys %{$resource{cft}}){
        my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'ringtimeout', prov_subscriber => $prov_subs)->first;
        $ringtimeout_preference = $ringtimeout_preference ? $ringtimeout_preference->value : undef;
        $resource{cft}{ringtimeout} = $ringtimeout_preference;
    }

    $form //= $self->get_form($c);
    $form->clear();
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    for my $cf_type (qw/cfu cft cfb cfna cfs cfr cfo/) {
        unless ($allowed_prefs->{$cf_type}) {
            delete $resource{$cf_type};
        }
    }

    $self->expand_fields($c, \%resource);
    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search(
            { 'me.status' => { '!=' => 'terminated' } },
            { 'prefetch' => { 'provisioning_voip_subscriber' => 'voip_cf_mappings' },},
        );
    if ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
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
    my $allowed_prefs = NGCP::Panel::Utils::Preferences::get_subscriber_allowed_prefs(
            c => $c,
            prov_subscriber => $prov_subs,
            pref_list => [qw/cfu cfb cft cfna cfs cfr cfo/],
        );

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        run => 1,
    );

    for my $type (qw/cfu cfb cft cfna cfs cfr cfo/) {
        next unless "ARRAY" eq ref $resource->{$type}{destinations};
        next unless ($allowed_prefs->{$type});
        for my $d (@{ $resource->{$type}{destinations} }) {
            if (exists $d->{timeout} && ! is_int($d->{timeout})) {
                $c->log->error("Invalid timeout in '$type'");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid timeout in '$type'");
                return;
            }
            if (defined $d->{announcement_id}) {
                if('customhours' ne $d->{destination}){
                    $c->log->error("Invalid parameter 'announcement_id' for the destination '".$c->qs($d->{destination})."' in '$type'");
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid parameter 'announcement_id' for the destination '".$c->qs($d->{destination})."' in '$type'");
                    return;
                }elsif(! is_int($d->{announcement_id})){
                    $c->log->error("Invalid announcement_id in '$type'");
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid announcement_id in '$type'");
                    return;
                }elsif(! $c->model('DB')->resultset('voip_sound_handles')->search_rs({
                       'me.id' => $d->{announcement_id},
                       'group.name' => 'custom_announcements',
                    },{
                        'join' => 'group'
                    }
                )->first() ){
                    $c->log->error("Unknown announcement_id in '$type'");
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown announcement_id in '$type'");
                    return;
                }
            }
        }
    }

    for my $type (qw/cfu cfb cft cfna cfs cfr cfo/) {
        next unless ($allowed_prefs->{$type});
        my $mapping = $c->model('DB')->resultset('voip_cf_mappings')->search_rs({
            subscriber_id => $prov_subscriber_id,
            type => $type,
        });
        my $mapping_count = $mapping->count;
        my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, prov_subscriber => $prov_subs, attribute => $type);
        my ($dset, $tset, $sset, $bset);
        if ($mapping_count == 0) {
            next unless (defined $resource->{$type});
            $mapping = $c->model('DB')->resultset('voip_cf_mappings')->create({
                subscriber_id => $prov_subscriber_id,
                type => $type,
            });
            $mapping->discard_changes; # get our row

            my $sets_forms = {
                source_set => "NGCP::Panel::Form::CallForward::CFSourceSetAPI",
                bnumber_set => "NGCP::Panel::Form::CallForward::CFBNumberSetAPI",
                destination_set => "NGCP::Panel::Form::CallForward::CFDestinationSetAPI",
                time_set => "NGCP::Panel::Form::CallForward::CFTimeSetAPI"
            };
            foreach my $set (keys %$sets_forms) {
                my $req_set = delete $resource->{$type}->{$set};
                if ($req_set) {
                    $req_set->{subscriber_id} = $prov_subs->id;
                    my $form = $sets_forms->{$set};
                    last unless $self->validate_form(
                        c => $c,
                        resource => $req_set,
                        form => (NGCP::Panel::Form::get("$form", $c)),
                    );
                    if ($set eq 'source_set') {
                        $sset = $mapping->create_related('source_set', $req_set);
                        $mapping->update({source_set_id => $sset->id});

                    }
                    if ($set eq 'destination_set') {
                        $dset = $mapping->create_related('destination_set', $req_set);
                        $mapping->update({destination_set_id => $dset->id});
                    }
                    if ($set eq 'bnumber_set') {
                        $bset = $mapping->create_related('bnumber_set', $req_set);
                        $mapping->update({bnumber_set_id => $bset->id});
                    }
                    if ($set eq 'time_set') {
                        $tset = $mapping->create_related('time_set', $req_set);
                        $mapping->update({time_set_id => $tset->id});
                    }
                }
            }
        } elsif ($mapping_count > 1) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Not a simple cf. Multiple $type-s configured.");
            return;
        } else { # count is 1
            $mapping = $mapping->first;
            $dset = $mapping->destination_set;
            $tset = $mapping->time_set;
            $sset = $mapping->source_set;
            $bset = $mapping->bnumber_set;
        }

        try {
            if($cf_preference->first) {
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
            my $domain = $prov_subs->domain->domain // '';
            my $old_autoattendant = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($dset);
            if ($dset) {
                if ((defined $resource->{$type}{destinations}) && @{ $resource->{$type}{destinations}}) {
                    $dset->voip_cf_destinations->delete; #empty dset
                } else {
                    $dset->delete; # delete dset
                    $mapping_count = 0; # auto deleted by mysql
                }
            } else {
                if ((defined $resource->{$type}{destinations}) && @{ $resource->{$type}{destinations}}) {
                    $dset = $mapping->create_related('destination_set', {'name' => "quickset_$type", subscriber_id => $prov_subscriber_id,} );
                    $mapping->update({destination_set_id => $dset->id});
                }
            }
            if ($tset) {
                if ((defined $resource->{$type}{times}) && @{ $resource->{$type}{times}}) {
                    $tset->voip_cf_periods->delete; #empty tset
                } else {
                    $mapping_count && $mapping->update({time_set_id => undef});
                    if ($tset->name =~ m/^quickset_/) {
                        $tset->delete; # delete tset
                    }
                }
            } else {
                if ((defined $resource->{$type}{times}) && @{ $resource->{$type}{times}}) {
                    $tset = $mapping->create_related('time_set', {'name' => "quickset_$type", subscriber_id => $prov_subscriber_id,} );
                    $mapping->update({time_set_id => $tset->id});
                }
            }
            if ($sset) {
                if ((defined $resource->{$type}{sources}) && @{ $resource->{$type}{sources}}) {
                    $sset->voip_cf_sources->delete; #empty sset
                } else {
                    $mapping_count && $mapping->update({source_set_id => undef});
                    if ($sset->name =~ m/^quickset_/) {
                        $sset->delete; # delete sset
                    }
                }
            } else {
                if ((defined $resource->{$type}{sources}) && @{ $resource->{$type}{sources}}) {
                    $sset = $mapping->create_related('source_set', {
                        name => "quickset_$type",
                        subscriber_id => $prov_subscriber_id,
                        mode => $resource->{$type}{sources_mode},
                        is_regex => $resource->{$type}{sources_is_regex},
                    });
                    $mapping->update({source_set_id => $sset->id});
                }
            }
            if ($bset) {
                if ((defined $resource->{$type}{bnumbers}) && @{ $resource->{$type}{bnumbers}}) {
                    $bset->voip_cf_bnumbers->delete; #empty bset
                } else {
                    $mapping_count && $mapping->update({bnumber_set_id => undef});
                    if ($bset->name =~ m/^quickset_/) {
                        $bset->delete; # delete bset
                    }
                }
            } else {
                if ((defined $resource->{$type}{bnumbers}) && @{ $resource->{$type}{bnumbers}}) {
                    $bset = $mapping->create_related('bnumber_set', {
                        name => "quickset_$type",
                        subscriber_id => $prov_subscriber_id,
                        mode => $resource->{$type}{bnumbers_mode},
                        is_regex => $resource->{$type}{bnumbers_is_regex},
                    });
                    $mapping->update({bnumber_set_id => $bset->id});
                }
            }
            for my $d (@{ $resource->{$type}{destinations} }) {
                delete $d->{destination_set_id};
                delete $d->{simple_destination};
                $d->{destination} = NGCP::Panel::Utils::Subscriber::field_to_destination(
                        destination => $d->{destination},
                        number => $number,
                        domain => $domain,
                        uri => $d->{destination},
                        cf_type => $type,
                        c => $c,
                        subscriber => $item,
                    );
                $dset->voip_cf_destinations->update_or_create($d);
            }

            for my $t (@{ $resource->{$type}{times} }) {
                delete $t->{time_set_id};
                $tset->voip_cf_periods->update_or_create($t);
            }
            for my $s (@{ $resource->{$type}{sources} }) {
                delete $s->{source_set_id};
                $sset->voip_cf_sources->update_or_create($s);
            }
            for my $b (@{ $resource->{$type}{bnumbers} }) {
                delete $b->{bnumber_set_id};
                $bset->voip_cf_bnumbers->update_or_create($b);
            }
            if (@{ $resource->{$type}{sources} } > 0 &&
                $sset->mode ne $resource->{$type}{sources_mode}) {
                $sset->update({mode => $resource->{$type}{sources_mode}});
            }
            if (@{ $resource->{$type}{sources} } > 0 &&
                $sset->is_regex ne $resource->{$type}{sources_is_regex}) {
                $sset->update({is_regex => $resource->{$type}{sources_is_regex}});
            }
            if (@{ $resource->{$type}{bnumbers} } > 0 &&
                $bset->mode ne $resource->{$type}{bnumbers_mode}) {
                $bset->update({mode => $resource->{$type}{bnumbers_mode}});
            }
            if (@{ $resource->{$type}{bnumbers} } > 0 &&
                $bset->is_regex ne $resource->{$type}{bnumbers_is_regex}) {
                $bset->update({is_regex => $resource->{$type}{bnumbers_is_regex}});
            }

            $dset->discard_changes if $dset; # update destinations
            my $new_autoattendant = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($dset);
            NGCP::Panel::Utils::Subscriber::check_cf_ivr(
                c => $c, schema => $c->model('DB'),
                subscriber => $item,
                old_aa => $old_autoattendant,
                new_aa => $new_autoattendant,
            );

            unless ( $dset && $dset->voip_cf_destinations->count ) {
                $mapping->delete;
                $cf_preference->delete;
            }
            
        } catch($e) {
            $c->log->error("Error Updating '$type': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "CallForward '$type' could not be updated.");
            return;
        }
    }

    if ($allowed_prefs->{cft} && $resource->{cft}{ringtimeout} && $resource->{cft}{ringtimeout} > 0) {
        my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'ringtimeout', prov_subscriber => $prov_subs);

        if($ringtimeout_preference->first) {
            $ringtimeout_preference->first->update({
                value => $resource->{cft}{ringtimeout},
            });
        } else {
            $ringtimeout_preference->create({
                value => $resource->{cft}{ringtimeout},
            });
        }
    } elsif ($c->model('DB')->resultset('voip_cf_mappings')->search_rs({
            subscriber_id => $prov_subs->id,
            type => 'cft',
            enabled => 1,
        })->count == 0) {
        NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c,
            attribute => 'ringtimeout',
            prov_subscriber => $prov_subs)->delete;
    }

    $item->discard_changes;
    return $item;
}

sub _contents_from_cfm {
    my ($self, $c, $cfm_item, $sub) = @_;
    my (@times, @destinations, @sources, @bnumbers);
    my $timeset_item = $cfm_item->time_set;
    my $dset_item = $cfm_item->destination_set;
    my $sourceset_item = $cfm_item->source_set;
    my $sourceset_mode = $sourceset_item ? $sourceset_item->mode : 'whitelist';
    my $sourceset_is_regex = $sourceset_item ? $sourceset_item->is_regex : 0;
    my $bnumberset_item = $cfm_item->bnumber_set;
    my $bnumberset_mode = $bnumberset_item ? $bnumberset_item->mode : 'whitelist';
    my $bnumberset_is_regex = $bnumberset_item ? $bnumberset_item->is_regex : 0;
    my $sourceset = $sourceset_item ? { $sourceset_item->get_inflated_columns } : undef;
    my $dset = $dset_item ? { $dset_item->get_inflated_columns } : undef;
    my $bnumberset = $bnumberset_item ? { $bnumberset_item->get_inflated_columns } : undef;
    my $timeset = $timeset_item ? { $timeset_item->get_inflated_columns } : undef;
    for my $time ($timeset_item ? $timeset_item->voip_cf_periods->all : () ) {
        push @times, {$time->get_inflated_columns};
        delete @{$times[-1]}{'time_set_id', 'id'};
    }
    for my $dest ($dset_item ? $dset_item->voip_cf_destinations->all : () ) {
        my ($d, $duri) = NGCP::Panel::Utils::Subscriber::destination_to_field($dest->destination);
        my $deflated;
        if($d eq "uri") {
            $deflated = NGCP::Panel::Utils::Subscriber::uri_deflate($c, $duri, $sub) if $d eq "uri";
            $d = $dest->destination;
        }
        push @destinations, {$dest->get_inflated_columns,
                destination => $d,
                $deflated ? (simple_destination => $deflated) : (),
            };
        delete @{$destinations[-1]}{'destination_set_id', 'id'};
    }
    for my $source ($sourceset_item ? $sourceset_item->voip_cf_sources->all : () ) {
        push @sources, {$source->get_inflated_columns};
        delete @{$sources[-1]}{'source_set_id', 'id'};
    }
    for my $bnumber ($bnumberset_item ? $bnumberset_item->voip_cf_bnumbers->all : () ) {
        push @bnumbers, {$bnumber->get_inflated_columns};
        delete @{$bnumbers[-1]}{'bnumber_set_id', 'id'};
    }
    return {times => \@times, destinations => \@destinations,
            sources => \@sources, sources_mode => $sourceset_mode, sources_is_regex => $sourceset_is_regex,
            bnumbers => \@bnumbers, bnumbers_mode => $bnumberset_mode, bnumbers_is_regex => $bnumberset_is_regex,
            destination_set => $dset, source_set => $sourceset,
            bnumber_set => $bnumberset, time_set => $timeset};
}

1;
# vim: set tabstop=4 expandtab:
