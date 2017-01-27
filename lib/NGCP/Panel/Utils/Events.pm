package NGCP::Panel::Utils::Events;

use Sipwise::Base;

use NGCP::Panel::Utils::DateTime qw();

sub insert_deferred {
    my %params = @_;
    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my $events_to_create = $params{events_to_create} // [];
    while (my $event = shift @$events_to_create) {
        insert(c => $c, schema => $schema,
            %$event
        );
    }
}

sub insert {
    my %params = @_;
    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my $type = $params{type};
    my $subscriber = $params{subscriber};
    my $old = $params{old};
    my $new = $params{new};
    my $old_aliases = $params{old_aliases};
    my $old_pilot_aliases = $params{old_pilot_aliases};
    my $new_aliases = $params{new_aliases}; #to pass cleared aliases upon termination, as aliases are removed via trigger
    my $new_pilot_aliases = $params{new_pilot_aliases};

    #reload it usually:
    $subscriber = $schema->resultset('voip_subscribers')->find({
        id => (defined $subscriber ? $subscriber->id : $params{subscriber_id}),
    });

    my $now_hires = NGCP::Panel::Utils::DateTime::current_local_hires;
    my $customer = $subscriber->contract;
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    my $tags_rs = $schema->resultset('events_tag');
    my $relations_rs = $schema->resultset('events_relation');

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

    save_voip_number(
        schema => $schema,
        event => $event,
        number => $subscriber->primary_number,
        types_prefix => 'primary_number_',
        now_hires => $now_hires,
        tags_rs => $tags_rs,
        relations_rs => $relations_rs,
    );

    save_subscriber_profile(
        schema => $schema,
        event => $event,
        subscriber_profile => ($prov_subscriber ? $prov_subscriber->voip_subscriber_profile : undef),
        types_prefix => 'subscriber_profile_',
        now_hires => $now_hires,
        tags_rs => $tags_rs,
        relations_rs => $relations_rs,
    );

    save_subscriber_profile_set(
        schema => $schema,
        event => $event,
        subscriber_profile_set => ($prov_subscriber ? $prov_subscriber->voip_subscriber_profile_set : undef),
        types_prefix => 'subscriber_profile_set_',
        now_hires => $now_hires,
        tags_rs => $tags_rs,
        relations_rs => $relations_rs,
    );

    save_first_non_primary_alias(
        schema => $schema,
        event => $event,
        (defined $old_aliases ? (aliases => $old_aliases) : (prov_subscriber => $prov_subscriber)),
        types_prefix => '',
        types_suffix => '_before',
        now_hires => $now_hires,
        tags_rs => $tags_rs,
    );
    save_first_non_primary_alias(
        schema => $schema,
        event => $event,
        (defined $new_aliases ? (aliases => $new_aliases) : (prov_subscriber => $prov_subscriber)),
        types_prefix => '',
        types_suffix => '_after',
        now_hires => $now_hires,
        tags_rs => $tags_rs,
    );

    my $pilot_subscriber = _get_pilot_subscriber(
        c => $c,
        schema => $schema,
        subscriber => $subscriber,
        customer => $customer,
        prov_subscriber => $prov_subscriber,
    );
    if ($pilot_subscriber) {
        $event->create_related("relation_data", {
            relation_id => $relations_rs->find({ type => 'pilot_subscriber_id' })->id,
            val => $pilot_subscriber->id,
            event_timestamp => $now_hires,
        });
        my $pilot_prov_subscriber = $pilot_subscriber->provisioning_voip_subscriber;
        save_voip_number(
            schema => $schema,
            event => $event,
            number => $pilot_subscriber->primary_number,
            types_prefix => 'pilot_primary_number_',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
            relations_rs => $relations_rs,
        );
        save_subscriber_profile(
            schema => $schema,
            event => $event,
            subscriber_profile => ($pilot_prov_subscriber ? $pilot_prov_subscriber->voip_subscriber_profile : undef),
            types_prefix => 'pilot_subscriber_profile_',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
            relations_rs => $relations_rs,
        );

        save_subscriber_profile_set(
            schema => $schema,
            event => $event,
            subscriber_profile_set => ($pilot_prov_subscriber ? $pilot_prov_subscriber->voip_subscriber_profile_set : undef),
            types_prefix => 'pilot_subscriber_profile_set_',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
            relations_rs => $relations_rs,
        );

        save_first_non_primary_alias(
            schema => $schema,
            event => $event,
            (defined $old_pilot_aliases ? (aliases => $old_pilot_aliases) : (prov_subscriber => $pilot_prov_subscriber)),
            types_prefix => 'pilot_',
            types_suffix => '_before',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
        );
        save_first_non_primary_alias(
            schema => $schema,
            event => $event,
            (defined $new_pilot_aliases ? (aliases => $new_pilot_aliases) : (prov_subscriber => $pilot_prov_subscriber)),
            types_prefix => 'pilot_',
            types_suffix => '_after',
            now_hires => $now_hires,
            tags_rs => $tags_rs,
        );
    }

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
    $now_hires //= NGCP::Panel::Utils::DateTime::current_local_hires;
    $customer //= $subscriber->contract;
    $prov_subscriber //= $subscriber->provisioning_voip_subscriber;
    my $pilot_subscriber = undef;
    my $bm_actual = get_actual_billing_mapping(c => $c,schema => $schema, contract => $customer, now => $now_hires);
    if ($bm_actual->billing_mappings->first->product->class eq 'pbxaccount') {
        if ($prov_subscriber and $prov_subscriber->is_pbx_pilot) {
            $pilot_subscriber = $subscriber;
        } else {
            $pilot_subscriber = $customer->voip_subscribers->search({
                'provisioning_voip_subscriber.is_pbx_pilot' => 1,
            },{
                join => 'provisioning_voip_subscriber',
            })->first;
        }
    }
    return $pilot_subscriber;
}

sub save_voip_number {
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

sub save_subscriber_profile {
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

sub save_subscriber_profile_set {
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

sub save_first_non_primary_alias {
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

sub _get_aliases_sorted_rs {
    my $prov_subscriber = shift;
    return $prov_subscriber->voip_dbaliases->search_rs({
        is_primary => 0,
    },{
        #previously in ngcpcfg: #order_by => { -asc => ['is_primary', 'id'] },
        order_by => { -asc => 'is_primary' },
    });
}

sub get_aliases_snapshot {
    my %params = @_;
    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my @aliases = ();
    my @pilot_aliases = ();
    my $subscriber = $params{subscriber} // $schema->resultset('voip_subscribers')->find({
        id => $params{subscriber_id},
    });
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;
    foreach my $alias (_get_aliases_sorted_rs($prov_subscriber)->all) {
        push(@aliases,{ $alias->get_inflated_columns });
    }
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
    }
    return { old_aliases => \@aliases, old_pilot_aliases => \@pilot_aliases };
}

sub get_actual_billing_mapping {
    my %params = @_;
    my ($c,$schema,$contract,$now) = @params{qw/c schema contract now/};
    $schema //= $c->model('DB');
    $now //= NGCP::Panel::Utils::DateTime::current_local;
    my $contract_create = NGCP::Panel::Utils::DateTime::set_local_tz($contract->create_timestamp // $contract->modify_timestamp);
    my $dtf = $schema->storage->datetime_parser;
    $now = $contract_create if $now < $contract_create; #if there is no mapping starting with or before $now, it would returns the mapping with max(id):
    return $schema->resultset('billing_mappings_actual')->search({ contract_id => $contract->id },{bind => [ ( $dtf->format_datetime($now) ) x 2, ($contract->id) x 2 ],})->first;
}

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
