package NGCP::Panel::Utils::CallForwards;
use strict;
use warnings;

use Sipwise::Base;

use NGCP::Panel::Utils::Subscriber qw();
use NGCP::Panel::Utils::Preferences qw();

sub update_cf_mappings {
    my %params = @_;

    my ($c,
        $schema,
        $resource,
        $item,
        $err_code,
        $validate_mapping_code,
        $validate_destination_set_code,
        $validate_time_set_code,
        $validate_source_set_code,
        $validate_bnumber_set_code,
        $params) = @params{qw/
        c
        schema
        resource
        item
        err_code
        validate_mapping_code
        validate_destination_set_code
        validate_time_set_code
        validate_source_set_code
        validate_bnumber_set_code
        params
    /};
    
    $params //= {};
    
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { };
    }
    if (!defined $validate_mapping_code || ref $validate_mapping_code ne 'CODE') {
        $validate_mapping_code = sub { return 1; };
    }
    if (!defined $validate_destination_set_code || ref $validate_destination_set_code ne 'CODE') {
        $validate_destination_set_code = sub { return 1; };
    }
    if (!defined $validate_time_set_code || ref $validate_time_set_code ne 'CODE') {
        $validate_time_set_code = sub { return 1; };
    }
    if (!defined $validate_source_set_code || ref $validate_source_set_code ne 'CODE') {
        $validate_source_set_code = sub { return 1; };
    }
    if (!defined $validate_bnumber_set_code || ref $validate_bnumber_set_code ne 'CODE') {
        $validate_bnumber_set_code = sub { return 1; };
    }

    if (ref $resource ne "HASH") {
        &{$err_code}("Must be a hash.");
        return;
    }

    delete $resource->{id};
    $schema //= $c->model('DB');
    
    return unless &$validate_mapping_code($resource);

    #return unless $self->validate_form(
    #    c => $c,
    #    form => $form,
    #    resource => $resource,
    #);

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
    my $dsets_rs = $schema->resultset('voip_cf_destination_sets');
    my $tsets_rs = $schema->resultset('voip_cf_time_sets');
    my $ssets_rs = $schema->resultset('voip_cf_source_sets');
    my $bsets_rs = $schema->resultset('voip_cf_bnumber_sets');
    my $dset_max_id = $dsets_rs->search( undef, { for => 'update' } )->get_column('id')->max() // -1;
    my $tset_max_id = $tsets_rs->search( undef, { for => 'update' } )->get_column('id')->max() // -1;
    my $sset_max_id = $ssets_rs->search( undef, { for => 'update' } )->get_column('id')->max() // -1;
    my $bset_max_id = $bsets_rs->search( undef, { for => 'update' } )->get_column('id')->max() // -1;

    for my $type ( qw/cfu cfb cft cfna cfs cfr cfo/) {
        if (ref $resource->{$type} ne "ARRAY") {
            &{$err_code}("Invalid field '$type'. Must be an array.");
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
                return unless &$validate_destination_set_code($mapping->{destinationset});
                #$form = NGCP::Panel::Role::API::CFDestinationSets->get_form($c);
                #return unless $self->validate_form(
                #    c => $c,
                #    resource => $mapping->{destinationset},
                #    form => $form,
                #);
                if (! exists $mapping->{destinationset}->{destinations} ) {
                    $mapping->{destinationset}->{destinations} = [];
                }
                
                if (!check_destinations(
                        c => $c,
                        schema => $schema,
                        resource => $mapping->{destinationset},
                        err_code => $err_code,
                    )) {
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
                &{$err_code}("Missing field 'destinationset' or 'destinationset_id' in '$type'.");
                return;
            }
            unless ($dset) {
                &{$err_code}("Invalid 'destinationset'. Could not be found.");
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
                return unless &$validate_time_set_code($mapping->{timeset});
                #$form = NGCP::Panel::Role::API::CFTimeSets->get_form($c);
                #return unless $self->validate_form(
                #    c => $c,
                #    resource => $mapping->{timeset},
                #    form => $form,
                #);
                if (! exists $mapping->{timeset}->{times} ) {
                    $mapping->{timeset}->{times} = [];
                }
                if (ref $mapping->{timeset}->{times} ne "ARRAY") {
                    &{$err_code}("Invalid field 'times'. Must be an array.");
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
                &{$err_code}("Invalid 'timeset'. Could not be found.");
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
                return unless &$validate_source_set_code($mapping->{sourceset});
                #$form = NGCP::Panel::Role::API::CFSourceSets->get_form($c);
                #return unless $self->validate_form(
                #    c => $c,
                #    resource => $mapping->{sourceset},
                ##    form => $form,
                #);
                if (! exists $mapping->{sourceset}->{sources} ) {
                    $mapping->{sourceset}->{sources} = [];
                }
                if (ref $mapping->{sourceset}->{sources} ne "ARRAY") {
                    &{$err_code}("Invalid field 'sources'. Must be an array.");
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
                &{$err_code}("Invalid 'sourceset'. Could not be found.");
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
                return unless &$validate_bnumber_set_code($mapping->{bnumberset});
                #$form = NGCP::Panel::Role::API::CFBNumberSets->get_form($c);
                #return unless $self->validate_form(
                #    c => $c,
                #    resource => $mapping->{bnumberset},
                #    form => $form,
                #);
                if (! exists $mapping->{bnumberset}->{bnumbers} ) {
                    $mapping->{bnumberset}->{bnumbers} = [];
                }
                if (ref $mapping->{bnumberset}->{bnumbers} ne "ARRAY") {
                    &{$err_code}("Invalid field 'bnumbers'. Must be an array.");
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
                &{$err_code}("Invalid 'bnumberset'. Could not be found.");
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
        $schema->resultset('voip_cf_destination_sets')->populate(\@new_dsets);
        $schema->resultset('voip_cf_time_sets')->populate(\@new_tsets);
        $schema->resultset('voip_cf_source_sets')->populate(\@new_ssets);
        $schema->resultset('voip_cf_bnumber_sets')->populate(\@new_bsets);
        $schema->resultset('voip_cf_destinations')->populate(\@new_destinations);
        $schema->resultset('voip_cf_periods')->populate(\@new_times);
        $schema->resultset('voip_cf_sources')->populate(\@new_sources);
        $schema->resultset('voip_cf_bnumbers')->populate(\@new_bnumbers);

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
                    c => $c, schema => $schema,
                    subscriber_id => $item->id,
                    type => 'end_ivr',
                );
            }
        } elsif ($autoattendant_count < 0) {
            while ($autoattendant_count != 0) {
                $autoattendant_count++;
                NGCP::Panel::Utils::Events::insert(
                    c => $c, schema => $schema,
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
        } elsif ($schema->resultset('voip_cf_mappings')->search_rs({
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
        &{$err_code}("Failed to create cfmapping.");
        return;
    };

    return $item;
}

sub check_destinations {
    
    my %params = @_;
    
    my ($c,
        $schema,
        $resource,
        $err_code) = @params{qw/
        c
        schema
        resource
        err_code
    /};
    
    $schema //= $c->model('DB');
    
    if (ref $resource->{destinations} ne "ARRAY") {
        &{$err_code}("Invalid field 'destinations'. Must be an array.");
        return;
    }
    for my $d (@{ $resource->{destinations} }) {
        if (ref $d ne "HASH") {
            &{$err_code}("Invalid element in array 'destinations'. Must be an object.");
            return;
        }
        if (exists $d->{timeout} && ! is_int($d->{timeout})) {
            $c->log->error("Invalid timeout for the destination '".$c->qs($d->{destination})."'");
            &{$err_code}("Invalid timeout for the destination '".$c->qs($d->{destination})."'");
            return;
        }
        if (exists $d->{priority} && ! is_int($d->{priority})) {
            $c->log->error("Invalid priority for the destination '".$c->qs($d->{destination})."'");
            &{$err_code}("Invalid priority for the destination '".$c->qs($d->{destination})."'");
            return;
        }
        if (defined $d->{announcement_id}) {
        #todo: I think that user expects that put and get will be the same
            if(('customhours' ne $d->{destination}) && ('sip:custom-hours@app.local' ne $d->{destination}) ){
                $c->log->error("Invalid parameter 'announcement_id' for the destination '".$c->qs($d->{destination})."'");
                &{$err_code}("Invalid parameter 'announcement_id' for the destination '".$c->qs($d->{destination})."'");
                return;
            }elsif(! is_int($d->{announcement_id})){
                $c->log->error("Invalid announcement_id");
                &{$err_code}("Invalid announcement_id");
                return;
            }elsif(! $schema->resultset('voip_sound_handles')->search_rs({
               'me.id' => $d->{announcement_id},
               'group.name' => 'custom_announcements',
            },{
                'join' => 'group',
            })->first() ){
                $c->log->error("Unknown announcement_id: ".$d->{announcement_id});
                &{$err_code}("Unknown announcement_id:".$d->{announcement_id});
                return;
            }
        }
    }
    return 1;
}

1;
