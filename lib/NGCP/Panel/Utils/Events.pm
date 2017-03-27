package NGCP::Panel::Utils::Events;

use Sipwise::Base;

use NGCP::Panel::Utils::DateTime qw();

use constant ENABLE_EVENTS => 1;
use constant CREATE_EVENT_PER_ALIAS => 1;

sub insert_deferred {
    my %params = @_;
    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my $events_to_create = $params{events_to_create} // [];
    my $inserted = 0;
    while (my $event = shift @$events_to_create) {
        if ('profile' eq $event->{type}) {
            $inserted += insert_profile_events(c => $c, schema => $schema,
                %$event
            );
        } else {
            $inserted += insert(c => $c, schema => $schema,
                %$event
            );
        }
    }
    return $inserted;
}

sub insert_profile_events {
    my %params = @_;

    return 0 unless ENABLE_EVENTS;

    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    #my $type = $params{type};
    #my $subscriber = $params{subscriber};
    my $old_profile_id = $params{old};
    my $new_profile_id = $params{new};

    my $now_hires = NGCP::Panel::Utils::DateTime::current_local_hires;
    #reload it usually:
    my $subscriber = $params{subscriber} // $schema->resultset('voip_subscribers')->find({
        id => $params{subscriber_id},
    });

    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;
    my $is_pilot = ($prov_subscriber && $prov_subscriber->is_pbx_pilot ? 1 : 0);
    my $pilot_subscriber = _get_pilot_subscriber(
        c => $c,
        schema => $schema,
        subscriber => $subscriber,
        prov_subscriber => $prov_subscriber,
        now_hires => $now_hires,
    );
    my $pilot_prov_subscriber;
    $pilot_prov_subscriber = $pilot_subscriber->provisioning_voip_subscriber if $pilot_subscriber;

    my ($old_aliases,$old_aliases_map) = _get_aliases_map($params{old_aliases},$prov_subscriber);
    my ($old_pilot_aliases,$old_pilot_aliases_map) = _get_aliases_map($params{old_pilot_aliases},$pilot_prov_subscriber);
    my ($new_aliases,$new_aliases_map) = _get_aliases_map($params{new_aliases},$prov_subscriber);
    my ($new_pilot_aliases,$new_pilot_aliases_map) = _get_aliases_map($params{new_pilot_aliases},$pilot_prov_subscriber);

    my $context = { c => $c, schema => $schema,
        subscriber => $subscriber,
        old_aliases => $params{old_aliases},
        new_aliases => $params{new_aliases},
        old_pilot_aliases => $params{old_pilot_aliases},
        new_pilot_aliases => $params{new_pilot_aliases},
        old_primary_alias => $params{old_primary_alias},
        new_primary_alias => $params{new_primary_alias},
        old_pilot_primary_alias => $params{old_pilot_primary_alias},
        new_pilot_primary_alias => $params{new_pilot_primary_alias},
        create_event_per_alias => 0,
        now_hires => $now_hires};

    my $inserted = 0;
    foreach my $new_alias (@$new_aliases) {
        $context->{alias} = $new_alias;
        if (not exists $old_aliases_map->{$new_alias}) {
            if (not $is_pilot and exists $old_pilot_aliases_map->{$new_alias}) {
                #aliases moved from pilot to subs
                if ($pilot_prov_subscriber) {
                    $context->{old} = $pilot_prov_subscriber->profile_id;
                    $context->{new} = $new_profile_id;
                    $inserted += _insert_profile_event($context);
                }
            } else {
                #aliases added
                $context->{old} = undef;
                $context->{new} = $new_profile_id;
                $inserted += _insert_profile_event($context);
            }
        } else {
            #no number change
            $context->{old} = $old_profile_id;
            $context->{new} = $new_profile_id;
            $inserted += _insert_profile_event($context);
        }
    }
    foreach my $old_alias (@$old_aliases) {
        $context->{alias} = $old_alias;
        if (not exists $new_aliases_map->{$old_alias}) {
            if (not $is_pilot and exists $new_pilot_aliases_map->{$old_alias}) {
                #aliases moved from subs to pilot
                if ($pilot_prov_subscriber) {
                    $context->{old} = $old_profile_id;
                    $context->{new} = $pilot_prov_subscriber->profile_id;
                    $inserted += _insert_profile_event($context);
                }
            } else {
                #aliases deleted
                $context->{old} = $old_profile_id;
                $context->{new} = undef;
                $inserted += _insert_profile_event($context);
            }
        } else {
            #no number change
        }
    }
    if ((scalar @$old_aliases) + (scalar @$new_aliases) == 0) {
        $context->{alias} = undef;
        $context->{old} = $old_profile_id;
        $context->{new} = $new_profile_id;
        $context->{create_event_per_alias} = undef;
        $inserted += _insert_profile_event($context);
    }

}

sub _insert_profile_event {

    my ($context) = @_;
    my $inserted = 0;
    if(($context->{old} // 0) != ($context->{new} // 0)) {
        if(defined $context->{old} && defined $context->{new}) {
            $context->{type} = "update_profile";
        } elsif(defined $context->{new}) {
            $context->{type} = "start_profile";
        } else {
            $context->{type} = "end_profile";
        }
        $inserted += insert(%$context);
    }
    return $inserted;

}

sub insert {
    my %params = @_;

    return 0 unless ENABLE_EVENTS;

    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my $type = $params{type};
    #my $subscriber = $params{subscriber};
    my $old = $params{old};
    my $new = $params{new};
    my $old_aliases = $params{old_aliases};
    my $old_pilot_aliases = $params{old_pilot_aliases};
    my $new_aliases = $params{new_aliases}; #to pass cleared aliases upon termination, as aliases are removed via trigger
    my $new_pilot_aliases = $params{new_pilot_aliases};
    my $old_primary_alias => $params{old_primary_alias};
    my $new_primary_alias => $params{new_primary_alias};
    my $old_pilot_primary_alias => $params{old_pilot_primary_alias};
    my $new_pilot_primary_alias => $params{new_pilot_primary_alias};
    my $create_event_per_alias = $params{create_event_per_alias} // CREATE_EVENT_PER_ALIAS;
    my $event_alias = $params{alias};
    my $now_hires = $params{now_hires} // NGCP::Panel::Utils::DateTime::current_local_hires;

    #reload it usually:
    my $subscriber = $params{subscriber} // $schema->resultset('voip_subscribers')->find({
        id => $params{subscriber_id},
    });

    my $customer = $subscriber->contract;
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;
    my $pilot_subscriber = $params{pilot_subscriber} // _get_pilot_subscriber(
        c => $c,
        schema => $schema,
        subscriber => $subscriber,
        customer => $customer,
        prov_subscriber => $prov_subscriber,
        now_hires => $now_hires,
    );

    my $tags_rs = $schema->resultset('events_tag');
    my $relations_rs = $schema->resultset('events_relation');

    my @aliases = ();
    if ($prov_subscriber) {
        if ($create_event_per_alias) { #create events for all aliases
            foreach my $alias (_get_aliases_sorted_rs($prov_subscriber)->all) {
                push(@aliases,$alias->username);
            }
        } elsif (defined $event_alias) { #create event for a specific alias
            push(@aliases,$event_alias);
        }
        unless ((scalar @aliases) > 0) { #create event for no alias
            push(@aliases,undef);
        }
    }

    my $inserted = 0;
    foreach my $alias_username (@aliases) {
        my $event = $schema->resultset('events')->create({
            type => $type,
            subscriber_id => $subscriber->id,
            reseller_id => $customer->contact->reseller_id,
            old_status => $old // '',
            new_status => $new // '',
            timestamp => $now_hires,
            export_status => 'unexported',
            exported_at => undef,
        });

        _save_voip_number(
            schema => $schema,
            event => $event,
            number => $subscriber->primary_number,
            types_prefix => 'primary_number_',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
            relations_rs => $relations_rs,
        );

        _save_subscriber_profile(
            schema => $schema,
            event => $event,
            subscriber_profile => ($prov_subscriber ? $prov_subscriber->voip_subscriber_profile : undef),
            types_prefix => 'subscriber_profile_',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
            relations_rs => $relations_rs,
        );

        _save_subscriber_profile_set(
            schema => $schema,
            event => $event,
            subscriber_profile_set => ($prov_subscriber ? $prov_subscriber->voip_subscriber_profile_set : undef),
            types_prefix => 'subscriber_profile_set_',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
            relations_rs => $relations_rs,
        );

        _save_first_non_primary_alias(
            schema => $schema,
            event => $event,
            (defined $old_aliases ? (aliases => $old_aliases) : (prov_subscriber => $prov_subscriber)),
            types_prefix => '',
            types_suffix => '_before',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
        );
        _save_first_non_primary_alias(
            schema => $schema,
            event => $event,
            (defined $new_aliases ? (aliases => $new_aliases) : (prov_subscriber => $prov_subscriber)),
            types_prefix => '',
            types_suffix => '_after',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
        );

        _save_primary_alias(
            schema => $schema,
            event => $event,
            (defined $old_primary_alias ? (alias => $old_primary_alias) : (prov_subscriber => $prov_subscriber)),
            types_prefix => '',
            types_suffix => '_before',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
        );
        _save_primary_alias(
            schema => $schema,
            event => $event,
            (defined $new_primary_alias ? (alias => $new_primary_alias) : (prov_subscriber => $prov_subscriber)),
            types_prefix => '',
            types_suffix => '_after',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
        );

        _save_alias(
            schema => $schema,
            event => $event,
            alias_username => $alias_username,
            now_hires => $now_hires,
            tags_rs => $tags_rs,
        );

        if ($pilot_subscriber) {
            $event->create_related("relation_data", {
                relation_id => $relations_rs->find({ type => 'pilot_subscriber_id' })->id,
                val => $pilot_subscriber->id,
                event_timestamp => $now_hires,
            });
            my $pilot_prov_subscriber = $pilot_subscriber->provisioning_voip_subscriber;
            _save_voip_number(
                schema => $schema,
                event => $event,
                number => $pilot_subscriber->primary_number,
                types_prefix => 'pilot_primary_number_',
                now_hires => $now_hires,
                tags_rs => $tags_rs,
                relations_rs => $relations_rs,
            );
            _save_subscriber_profile(
                schema => $schema,
                event => $event,
                subscriber_profile => ($pilot_prov_subscriber ? $pilot_prov_subscriber->voip_subscriber_profile : undef),
                types_prefix => 'pilot_subscriber_profile_',
                now_hires => $now_hires,
                tags_rs => $tags_rs,
                relations_rs => $relations_rs,
            );

            _save_subscriber_profile_set(
                schema => $schema,
                event => $event,
                subscriber_profile_set => ($pilot_prov_subscriber ? $pilot_prov_subscriber->voip_subscriber_profile_set : undef),
                types_prefix => 'pilot_subscriber_profile_set_',
                now_hires => $now_hires,
                tags_rs => $tags_rs,
                relations_rs => $relations_rs,
            );

            _save_first_non_primary_alias(
                schema => $schema,
                event => $event,
                (defined $old_pilot_aliases ? (aliases => $old_pilot_aliases) : (prov_subscriber => $pilot_prov_subscriber)),
                types_prefix => 'pilot_',
                types_suffix => '_before',
                now_hires => $now_hires,
                tags_rs => $tags_rs,
            );
            _save_first_non_primary_alias(
                schema => $schema,
                event => $event,
                (defined $new_pilot_aliases ? (aliases => $new_pilot_aliases) : (prov_subscriber => $pilot_prov_subscriber)),
                types_prefix => 'pilot_',
                types_suffix => '_after',
                now_hires => $now_hires,
                tags_rs => $tags_rs,
            );

            _save_primary_alias(
                schema => $schema,
                event => $event,
                (defined $old_pilot_primary_alias ? (alias => $old_pilot_primary_alias) : (prov_subscriber => $pilot_prov_subscriber)),
                types_prefix => 'pilot_',
                types_suffix => '_before',
                now_hires => $now_hires,
                tags_rs => $tags_rs,
            );
            _save_primary_alias(
                schema => $schema,
                event => $event,
                (defined $new_pilot_primary_alias ? (aliases => $new_pilot_primary_alias) : (prov_subscriber => $pilot_prov_subscriber)),
                types_prefix => 'pilot_',
                types_suffix => '_after',
                now_hires => $now_hires,
                tags_rs => $tags_rs,
            );
        }
        $inserted++;
        $c->log->debug('edr event "'. $type .'" inserted: subscriber id ' . $subscriber->id . ($alias_username ? ", alias $alias_username" : ''));
    }
    return $inserted;
}

sub _get_pilot_subscriber {
    my %params = @_;
    my ($c,
        $schema,
        $subscriber,
        $customer,
        $prov_subscriber,
        $now_hires,
        ) = @params{qw/
        c
        schema
        subscriber
        customer
        prov_subscriber
        now_hires
    /};
    #now_hires
    $schema //= $c->model('DB');
    #$now_hires //= NGCP::Panel::Utils::DateTime::current_local_hires;
    $customer //= $subscriber->contract;
    $prov_subscriber //= $subscriber->provisioning_voip_subscriber;
    my $pilot_subscriber = undef;
    #my $bm_actual = _get_actual_billing_mapping(c => $c,schema => $schema, contract => $customer, now => $now_hires);
    #if ($bm_actual->billing_mappings->first->product->class eq 'pbxaccount') {
        if ($prov_subscriber and $prov_subscriber->is_pbx_pilot) {
            $pilot_subscriber = $subscriber;
        } else {
            $pilot_subscriber = $customer->voip_subscribers->search({
                'provisioning_voip_subscriber.is_pbx_pilot' => 1,
            },{
                join => 'provisioning_voip_subscriber',
            })->first;
        }
    #}
    return $pilot_subscriber;
}

sub _save_voip_number {
    my %params = @_;
    my ($schema,
        $event,
        $number,
        $types_prefix,
        $now_hires,
        $tags_rs,
        $relations_rs) = @params{qw/
        schema
        event
        number
        types_prefix
        now_hires
        tags_rs
        relations_rs
    /};
    if ($number) {
        $tags_rs //= $schema->resultset('events_tag');
        $relations_rs //= $schema->resultset('events_relation');
        $event->create_related("relation_data", {
            relation_id => $relations_rs->find({ type => $types_prefix.'id' })->id,
            val => $number->id,
            event_timestamp => $now_hires,
        });
        if (length(my $cc = $number->cc) > 0) {
            $event->create_related("tag_data", {
                tag_id => $tags_rs->find({ type => $types_prefix.'cc' })->id,
                val => $cc,
                event_timestamp => $now_hires,
            });
        }
        if (length(my $ac = $number->ac) > 0) {
            $event->create_related("tag_data", {
                tag_id => $tags_rs->find({ type => $types_prefix.'ac' })->id,
                val => $ac,
                event_timestamp => $now_hires,
            });
        }
        if (length(my $sn = $number->sn) > 0) {
            $event->create_related("tag_data", {
                tag_id => $tags_rs->find({ type => $types_prefix.'sn' })->id,
                val => $sn,
                event_timestamp => $now_hires,
            });
        }
    }
}

sub _save_subscriber_profile {
    my %params = @_;
    my ($schema,
        $event,
        $subscriber_profile,
        $types_prefix,
        $now_hires,
        $tags_rs,
        $relations_rs) = @params{qw/
        schema
        event
        subscriber_profile
        types_prefix
        now_hires
        tags_rs
        relations_rs
    /};

    if ($subscriber_profile) {
        $tags_rs //= $schema->resultset('events_tag');
        $relations_rs //= $schema->resultset('events_relation');
        $event->create_related("relation_data", {
            relation_id => $relations_rs->find({ type => $types_prefix.'id' })->id,
            val => $subscriber_profile->id,
            event_timestamp => $now_hires,
        });
        $event->create_related("tag_data", {
            tag_id => $tags_rs->find({ type => $types_prefix.'name' })->id,
            val => $subscriber_profile->name,
            event_timestamp => $now_hires,
        });
    }
}

sub _save_subscriber_profile_set {
    my %params = @_;
    my ($schema,
        $event,
        $subscriber_profile_set,
        $types_prefix,
        $now_hires,
        $tags_rs,
        $relations_rs) = @params{qw/
        schema
        event
        subscriber_profile_set
        types_prefix
        now_hires
        tags_rs
        relations_rs
    /};

    if ($subscriber_profile_set) {
        $tags_rs //= $schema->resultset('events_tag');
        $relations_rs //= $schema->resultset('events_relation');
        $event->create_related("relation_data", {
            relation_id => $relations_rs->find({ type => $types_prefix.'id' })->id,
            val => $subscriber_profile_set->id,
            event_timestamp => $now_hires,
        });
        $event->create_related("tag_data", {
            tag_id => $tags_rs->find({ type => $types_prefix.'name' })->id,
            val => $subscriber_profile_set->name,
            event_timestamp => $now_hires,
        });
    }
}

sub _save_first_non_primary_alias {
    my %params = @_;
    my ($schema,
        $event,
        $aliases,
        $prov_subscriber,
        $types_prefix,
        $types_suffix,
        $now_hires,
        $tags_rs) = @params{qw/
        schema
        event
        aliases
        prov_subscriber
        types_prefix
        types_suffix
        now_hires
        tags_rs
    /};
    my $alias_username = undef;
    if ($aliases) {
        #my $alias = shift(sort { $a->{is_primary} <=> $b->{is_primary} || $a->{id} <=> $b->{id}; } @$aliases);
        my $alias = $aliases->[0]; #expect the ary sorted
        $alias_username = $alias->{username} if $alias;
    } elsif ($prov_subscriber) {
        my $alias = _get_aliases_sorted_rs($prov_subscriber)->first;
        $alias_username = $alias->username if $alias;
    }
    if ($alias_username) {
        $tags_rs //= $schema->resultset('events_tag');
        $event->create_related("tag_data", {
            tag_id => $tags_rs->find({ type => $types_prefix.'first_non_primary_alias_username'.$types_suffix })->id,
            val => $alias_username,
            event_timestamp => $now_hires,
        });
    }

}

sub _save_primary_alias {
    my %params = @_;
    my ($schema,
        $event,
        $alias,
        $prov_subscriber,
        $types_prefix,
        $types_suffix,
        $now_hires,
        $tags_rs) = @params{qw/
        schema
        event
        alias
        prov_subscriber
        types_prefix
        types_suffix
        now_hires
        tags_rs
    /};
    my $alias_username = undef;
    if ($alias) {
        $alias_username = $alias->{username} if $alias;
    } elsif ($prov_subscriber) {
        my $alias = _get_primary_alias($prov_subscriber);
        $alias_username = $alias->username if $alias;
    }
    if ($alias_username) {
        $tags_rs //= $schema->resultset('events_tag');
        $event->create_related("tag_data", {
            tag_id => $tags_rs->find({ type => $types_prefix.'primary_alias_username'.$types_suffix })->id,
            val => $alias_username,
            event_timestamp => $now_hires,
        });
    }

}

sub _save_alias {
    my %params = @_;
    my ($schema,
        $event,
        $alias_username,
        $now_hires,
        $tags_rs) = @params{qw/
        schema
        event
        alias_username
        now_hires
        tags_rs
    /};
    if ($alias_username) {
        $tags_rs //= $schema->resultset('events_tag');
        $event->create_related("tag_data", {
            tag_id => $tags_rs->find({ type => 'non_primary_alias_username' })->id,
            val => $alias_username,
            event_timestamp => $now_hires,
        });
    }
}

sub _get_aliases_sorted_rs {
    my ($prov_subscriber) = @_;
    return $prov_subscriber->voip_dbaliases->search_rs({
        is_primary => 0,
    },{
        #previously in ngcpcfg: #order_by => { -asc => ['is_primary', 'id'] },
        order_by => { -asc => 'id' },
    });
}

sub _get_primary_alias {
    my ($prov_subscriber) = @_;
    return $prov_subscriber->voip_dbaliases->search_rs({
        is_primary => 1,
    },undef)->first;
}

sub _get_aliases_map {
    my ($aliases, $prov_subscriber) = @_;
    my @alias_usernames = ();
    my %alias_map = ();
    if ('ARRAY' eq ref $aliases) {
        foreach my $alias (@$aliases) {
            $alias_map{$alias->{username}} = $alias;
            push(@alias_usernames,$alias->{username});
        }
    } else {
        if ($prov_subscriber) {
            foreach my $alias (_get_aliases_sorted_rs($prov_subscriber)->all) {
                $alias_map{$alias->username} = { $alias->get_inflated_columns };
                push(@alias_usernames,$alias->username);
            }
        }
    }
    return (\@alias_usernames,\%alias_map);
}

sub get_aliases_snapshot {
    my %params = @_;
    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my @aliases = ();
    my $primary_alias = undef;
    my @pilot_aliases = ();
    my $pilot_primary_alias = undef;
    if (ENABLE_EVENTS) {
        my $subscriber = $params{subscriber} // $schema->resultset('voip_subscribers')->find({
            id => $params{subscriber_id},
        });
        my $prov_subscriber = $subscriber->provisioning_voip_subscriber;
        foreach my $alias (_get_aliases_sorted_rs($prov_subscriber)->all) {
            push(@aliases,{ $alias->get_inflated_columns });
        }
        $primary_alias = _get_primary_alias($prov_subscriber);
        $primary_alias = $primary_alias->get_inflated_columns if $primary_alias;
        my $pilot_subscriber = _get_pilot_subscriber(
            c => $c,
            schema => $schema,
            subscriber => $subscriber,
            prov_subscriber => $prov_subscriber,
        );
        if ($pilot_subscriber) {
            my $pilot_prov_subscriber = $pilot_subscriber->provisioning_voip_subscriber;
            foreach my $alias (_get_aliases_sorted_rs($pilot_prov_subscriber)->all) {
                push(@pilot_aliases,{ $alias->get_inflated_columns });
            }
            $pilot_primary_alias = _get_primary_alias($pilot_prov_subscriber);
            $pilot_primary_alias = $pilot_primary_alias->get_inflated_columns if $pilot_primary_alias;
        }
    }
    return { old_aliases => \@aliases, old_pilot_aliases => \@pilot_aliases,
        old_primary_alias => $primary_alias, old_pilot_primary_alias => $pilot_primary_alias };
}

#sub _get_actual_billing_mapping {
#    my %params = @_;
#    my ($c,$schema,$contract,$now) = @params{qw/c schema contract now/};
#    $schema //= $c->model('DB');
#    $now //= NGCP::Panel::Utils::DateTime::current_local;
#    my $contract_create = NGCP::Panel::Utils::DateTime::set_local_tz($contract->create_timestamp // $contract->modify_timestamp);
#    my $dtf = $schema->storage->datetime_parser;
#    $now = $contract_create if $now < $contract_create; #if there is no mapping starting with or before $now, it would returns the mapping with max(id):
#    return $schema->resultset('billing_mappings_actual')->search({ contract_id => $contract->id },{bind => [ ( $dtf->format_datetime($now) ) x 2, ($contract->id) x 2 ],})->first;
#}

sub get_relation_value {
    my %params = @_;
    my ($c,$schema,$event,$type) = @params{qw/c schema event type/};
    $schema //= $c->model('DB');
    if ($event) {
        my $relations_rs = $schema->resultset('events_relation');
        my $relation_data = $event->relation_data->find({
            relation_id => $relations_rs->find({ type => $type })->id,
        });
        if ($relation_data) {
            return $relation_data->val;
        }
    }
    return undef;
}

sub get_tag_value {
    my %params = @_;
    my ($c,$schema,$event,$type) = @params{qw/c schema event type/};
    $schema //= $c->model('DB');
    if ($event) {
        my $tags_rs = $schema->resultset('events_tag');
        my $tag_data = $event->tag_data->find({
            tag_id => $tags_rs->find({ type => $type })->id,
        });
        if ($tag_data) {
            return $tag_data->val;
        }
    }
    return undef;
}

1;
