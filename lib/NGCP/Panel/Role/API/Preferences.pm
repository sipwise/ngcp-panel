package NGCP::Panel::Role::API::Preferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use Safe::Isa qw($_isa);
use Data::Validate::IP qw/is_ipv4 is_ipv6/;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Prosody;
use NGCP::Panel::Utils::XMLDispatcher;

sub get_form {
    my ($self, $c) = @_;
    return;
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;

    my $print_type = $type;
    $print_type = "customers" if $print_type eq "contracts";
    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:$print_type", href => sprintf("/api/%s/%d", $print_type, $item->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->get_resource($c, $item, $type);
    $hal->resource($resource);
    return $hal;
}

sub _check_profile {
    my ($self, $c, $pref_name, $attr) = @_;
    my $shown = $c->model('DB')->resultset('voip_preferences')->find({
        'attribute' => $pref_name
    });
    return unless($shown && $attr->{$shown->id});
    return 1;
}

sub get_resource {
    my ($self, $c, $item, $type) = @_;

    my $prefs;
    my %profile_attrs = (); # for filtering profiles based list
    my %profile_allowed_attrs; # for filtering subscriber attrs on its profile
    my $has_profile = 0;
    my $attr = 0;
    if($type eq "subscribers") {
        $prefs = $item->provisioning_voip_subscriber->voip_usr_preferences;
        my $profile = $item->provisioning_voip_subscriber->voip_subscriber_profile;
        if ($profile) {
            $has_profile = 1;
            %profile_allowed_attrs = map { $_ => 1 } $profile->profile_attributes->get_column('attribute_id')->all;
        }
    } elsif($type eq "profiles") {
        $attr = 1;
        %profile_attrs = map { $_ => 1 } $item->profile_attributes->get_column('attribute_id')->all;
        $prefs = $item->voip_prof_preferences;
    } elsif($type eq "domains") {
        $prefs = $item->provisioning_voip_domain->voip_dom_preferences;
    } elsif($type eq "peerings") {
        $prefs = $item->voip_peer_preferences;
    } elsif($type eq "contracts") {
        $prefs = $item->voip_contract_preferences->search(
                    { location_id => $c->request->param('location_id') || undef },
                    undef);
    } elsif($type eq "pbxdevicemodels") {
        $prefs = $item->voip_dev_preferences;
    } elsif($type eq "pbxdeviceprofiles") {
        $prefs = $item->voip_devprof_preferences;
    }
    $prefs = $prefs->search({
    }, {
        join => 'attribute',
        order_by => { '-asc' => 'id' },
    });

    my $resource;
    foreach my $pref($prefs->all) {
        my $value;
        my $processed = 0;

        if ($c->user->roles eq 'subscriberadmin') {
            my $attrname = $pref->attribute->attribute;
            unless ( $pref->attribute->expose_to_customer ) {
                $c->log->debug("skipping attribute $attrname, not exposing to customer");
                next;
            }

            if ($has_profile && !$profile_allowed_attrs{$pref->attribute_id}) {
                $c->log->debug("skipping attribute $attrname, not in profile");
                next;
            }
        }

        SWITCH: for ($pref->attribute->attribute) {
            /^rewrite_calle[re]_(in|out)_dpid$/ && do {
                if(exists $resource->{rewrite_rule_set}) {
                    $processed = 1;
                    last SWITCH;
                }
                do { $processed = 1; last SWITCH; }
                    if($attr && !$self->_check_profile($c, 'rewrite_rule_set', \%profile_attrs));
                my $col = $pref->attribute->attribute;
                $col =~ s/^rewrite_//;
                my $rwr_set = $c->model('DB')->resultset('voip_rewrite_rule_sets')->find({
                    $col => $pref->value,
                });
                if($rwr_set) {
                    $resource->{rewrite_rule_set} = $rwr_set->name;
                } else {
                    $c->log->error("no rewrite rule set for '".$pref->attribute->attribute."' with value '".$pref->value."' found, altough it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                $processed = 1;
                last SWITCH;
            };
            /^(adm_)?(cf_)?ncos_id$/ && do {
                my $pref_name = $pref->attribute->attribute;
                $pref_name =~ s/_id$//;

                do { $processed = 1; last SWITCH; }
                    if($attr && !$self->_check_profile($c, $pref_name, \%profile_attrs));

                my $ncos = $c->model('DB')->resultset('ncos_levels')->find({
                    id => $pref->value,
                });
                if($ncos) {
                    $resource->{$pref_name} = $ncos->level;
                } else {
                    $c->log->error("no ncos level for '".$pref->attribute->attribute."' with value '".$pref->value."' found, altough it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                $processed = 1;
                last SWITCH;
            };
            /^emergency_mapping_container_id$/ && do {
                my $pref_name = $pref->attribute->attribute;
                $pref_name =~ s/_id$//;

                do { $processed = 1; last SWITCH; }
                    if($attr && !$self->_check_profile($c, $pref_name, \%profile_attrs));

                my $container = $c->model('DB')->resultset('emergency_containers')->find({
                    id => $pref->value,
                });
                if($container) {
                    $resource->{$pref_name} = $container->name;
                } else {
                    $c->log->error("no emergency mapping container for '".$pref->attribute->attribute."' with value '".$pref->value."' found, altough it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                $processed = 1;
                last SWITCH;
            };
            /^(contract_)?sound_set$/ && do {
                # TODO: not applicable for domains, but for subs, check for contract_id!
                do { $processed = 1; last SWITCH; }
                    if($attr && !$self->_check_profile($c, $_, \%profile_attrs));

                my $set = $c->model('DB')->resultset('voip_sound_sets')->find({
                    id => $pref->value,
                });
                if($set) {
                    $resource->{$pref->attribute->attribute} = $set->name;
                } else {
                    $c->log->error("no sound set for '".$pref->attribute->attribute."' with value '".$pref->value."' found, altough it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                $processed = 1;
                last SWITCH;
            };
            /^(man_)?allowed_ips_grp$/ && do {
                my $pref_name = $pref->attribute->attribute;
                $pref_name =~ s/_grp$//;
                do { $processed = 1; last SWITCH; }
                    if($attr && !$self->_check_profile($c, $pref_name, \%profile_attrs));
                my $sets = $c->model('DB')->resultset('voip_allowed_ip_groups')->search({
                    group_id => $pref->value,
                }, {
                    order_by => { -asc => 'id' },
                });
                foreach my $set($sets->all) {
                    $resource->{$pref_name} = []
                        unless exists($resource->{$pref_name});
                    push @{ $resource->{$pref_name} }, $set->ipnet;
                }
                $processed = 1;
                last SWITCH;
            };
            # default
            if($attr && !$profile_attrs{$pref->attribute->id}) {
                $processed = 1; last SWITCH;
            }
            if($pref->attribute->internal != 0) {
                $processed = 1;
                last SWITCH;
            }
        } # SWITCH
        next if $processed;

        SWITCH: for ($pref->attribute->data_type) {
            /^int$/ && do {
                $value = int($pref->value) if(is_int($pref->value));
                last SWITCH;
            };
            /^boolean$/ && do {
                if (defined $pref->value) {
                    $value = ($pref->value ? JSON::true : JSON::false);
                }
                last SWITCH;
            };
            # default
            $value = $pref->value;
        } # SWITCH
        if($pref->attribute->max_occur != 1) {
            $resource->{$pref->attribute->attribute} = []
                unless(exists $resource->{$pref->attribute->attribute});
            push @{ $resource->{$pref->attribute->attribute} }, $value;
        } else {
            $resource->{$pref->attribute->attribute} = $value;
        }
    }

    if($type eq "domains") {
        $resource->{domain_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "subscribers") {
        $resource->{subscriber_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "profiles") {
        $resource->{profile_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "peerings") {
        $resource->{peering_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "pbxdevicemodels") {
        $resource->{device_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "pbxdeviceprofiles") {
        $resource->{profile_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "contracts") {
        $resource->{customer_id} = int($item->id);
        $resource->{id} = int($item->id);
        $prefs->first ? $resource->{location_id} = $prefs->first->location_id
                      : undef;
    }

    return $resource;
}

sub _item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    if($type eq "domains") {
        # we actually return the domain rs here, as we can easily
        # go to dom_preferences from there
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('domains');
        } elsif($c->user->roles eq "reseller") {
            $item_rs = $c->model('DB')->resultset('admins')->find(
                    { id => $c->user->id, } )
                ->reseller
                ->domain_resellers
                ->search_related('domain');
        }
    } elsif($type eq "profiles") {
        # we actually return the profile rs here, as we can easily
        # go to prof_preferences from there
        $item_rs = $c->model('DB')->resultset('voip_subscriber_profiles');
        if($c->user->roles eq "reseller") {
            $item_rs = $item_rs->search({
                'profile_set.reseller_id' => $c->user->reseller_id,
            },{
                join => 'profile_set',
            });
        }
    } elsif($type eq "subscribers") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'me.status' => { '!=' => 'terminated' }
            }, {
                join => { 'contract' => 'contact' }, #for filters
            });
        } elsif($c->user->roles eq "reseller") {
            $item_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'contact.reseller_id' => $c->user->reseller_id,
                'me.status' => { '!=' => 'terminated' },
            }, {
                join => { 'contract' => 'contact' },
            });
        } elsif ($c->user->roles eq 'subscriberadmin') {
            $item_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'contract.id' => $c->user->account_id,
                'me.status' => { '!=' => 'terminated' },
            },{
                join => 'contract',
            });
        }
    } elsif($type eq "peerings") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('voip_peer_hosts');
        } else {
            return;
        }
    } elsif($type eq "pbxdevicemodels") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('autoprov_devices');
            #don't select images
            #$item_rs = $c->model('DB')->resultset('autoprov_devices')->search_rs(
            #    undef,
            #    {
            #        'columns'
            #            => [qw/id reseller_id type vendor model front_image_type mac_image_type num_lines bootstrap_method bootstrap_uri extensions_num/]
            #    }
            #);
        } else {
            $item_rs = $c->model('DB')->resultset('autoprov_devices')->search({'reseller_id' => $c->user->reseller_id});
        }
    } elsif($type eq "pbxdeviceprofiles") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('autoprov_profiles');
        } else {
            $item_rs = $c->model('DB')->resultset('autoprov_profiles')->search({
                    'device.reseller_id' => $c->user->reseller_id
                },{
                    'join' => {'config' => 'device'},
            });
        }
    } elsif($type eq "contracts") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('contracts')->search({
                'me.status' => { '!=' => 'terminated' },
                'contact.reseller_id' => { '!=' => undef },

            },{
                join => 'contact',
            });
        } elsif($c->user->roles eq "reseller") {
            $item_rs = $c->model('DB')->resultset('contracts')->search({
                'contact.reseller_id' => $c->user->reseller_id,
                'me.status' => { '!=' => 'terminated' },
            }, {
                join => 'contact',
            });
        }
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id, $type) = @_;

    my $item_rs = $self->item_rs($c, $type);
    return $item_rs->find($id);
}

sub get_preference_rs {
    my ($self, $c, $type, $elem, $attr) = @_;

    my $rs;
    if($type eq "domains") {
        $rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
            c => $c,
            attribute => $attr,
            prov_domain => $elem,
        );
    } elsif($type eq "profiles") {
        $rs = NGCP::Panel::Utils::Preferences::get_prof_preference_rs(
            c => $c,
            attribute => $attr,
            profile => $elem,
        );
    } elsif($type eq "subscribers") {
        $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c,
            attribute => $attr,
            prov_subscriber => $elem,
            ($c->user->roles eq "subscriberadmin") ? (subscriberadmin => 1) : (),
        );
    } elsif($type eq "peerings") {
        $rs = NGCP::Panel::Utils::Preferences::get_peer_preference_rs(
            c => $c,
            attribute => $attr,
            peer_host => $elem,
        );
    } elsif($type eq "pbxdevicemodels") {
        $rs = NGCP::Panel::Utils::Preferences::get_dev_preference_rs(
            c => $c,
            attribute => $attr,
            device => $elem,
        );
    } elsif($type eq "pbxdeviceprofiles") {
        $rs = NGCP::Panel::Utils::Preferences::get_devprof_preference_rs(
            c => $c,
            attribute => $attr,
            profile => $elem,
        );
    } elsif($type eq "contracts") {
        $rs = NGCP::Panel::Utils::Preferences::get_contract_preference_rs(
            c => $c,
            attribute => $attr,
            contract => $elem,
            location_id => $c->request->param('location_id') || undef,
        );
    }
    return $rs;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $replace, $type) = @_;

    delete $resource->{id};
    my $accessor;
    my $elem;
    my $pref_type;
    my $reseller_id;
    my $full_rs;
    my $old_auth_prefs = {};

    if($type eq "domains") {
        delete $resource->{domain_id};
        delete $resource->{domainpreferences_id};
        delete $old_resource->{domain_id};
        delete $old_resource->{domainpreferences_id};
        $accessor = $item->domain;
        $elem = $item->provisioning_voip_domain;
        $full_rs = $elem->voip_dom_preferences;
        $pref_type = 'dom_pref';
        $reseller_id = $item->domain_resellers->first->reseller_id;
    } elsif($type eq "profiles") {
        delete $resource->{profile_id};
        delete $resource->{profilepreferences_id};
        delete $old_resource->{profile_id};
        delete $old_resource->{profilepreferences_id};
        $accessor = $item->id;
        $elem = $item;
        $full_rs = $elem->voip_prof_preferences;
        $pref_type = 'prof_pref';
        $reseller_id = $item->profile_set->reseller_id;
    } elsif($type eq "subscribers") {
        delete $resource->{subscriber_id};
        delete $resource->{subscriberpreferences_id};
        delete $old_resource->{subscriber_id};
        delete $old_resource->{subscriberpreferences_id};
        $accessor = $item->username . '@' . $item->domain->domain;
        $elem = $item->provisioning_voip_subscriber;
        $full_rs = $elem->voip_usr_preferences;
        if ($c->user->roles eq 'subscriberadmin') {
            $full_rs = $full_rs->search_rs({
                'attribute.expose_to_customer' => 1,
            },{
                join => 'attribute',
            });

            if ($elem && $elem->voip_subscriber_profile) {
                my @allowed_attr_ids = $elem->voip_subscriber_profile->profile_attributes
                    ->get_column('attribute_id')->all;
                $full_rs = $full_rs->search_rs({
                    'attribute.id' => { '-in' => \@allowed_attr_ids },
                });
            }
        }
        $pref_type = 'usr_pref';
        $reseller_id = $item->contract->contact->reseller_id;
    } elsif($type eq "peerings") {
        delete $resource->{peer_id};
        delete $resource->{peerpreferences_id};
        delete $old_resource->{peer_id};
        delete $old_resource->{peerpreferences_id};
        $accessor = $item->name;
        $elem = $item;
        $full_rs = $elem->voip_peer_preferences;
        $pref_type = 'peer_pref';
        $reseller_id = 1;
    } elsif($type eq "contracts") {
        delete $resource->{customer_id};
        delete $old_resource->{customer_id};
        delete $resource->{location_id};
        delete $old_resource->{location_id};
        $accessor = $item->id;
        $elem = $item;
        $full_rs = $elem->voip_contract_preferences->search_rs(
                    { location_id => $c->request->param('location_id') || undef },
                    undef);
        $pref_type = 'contract_pref';
        $reseller_id = $item->contact->reseller_id;
    } elsif($type eq "pbxdevicemodels") {
        delete $resource->{device_id};
        delete $old_resource->{device_id};
        delete $resource->{pbxdevicepreferences_id};
        delete $old_resource->{pbxdevicepreferences_id};
        $accessor = $item->id;
        $elem = $item;
        $full_rs = $elem->voip_dev_preferences->search_rs();
        $pref_type = 'dev_pref';
        $reseller_id = $item->reseller_id;
    } elsif($type eq "pbxdeviceprofiles") {
        delete $resource->{profile_id};
        delete $old_resource->{prof};
        delete $resource->{pbxdeviceprofilepreferences_id};
        delete $old_resource->{pbxdeviceprofilepreferences_id};
        $accessor = $item->id;
        $elem = $item;
        $full_rs = $elem->voip_devprof_preferences->search_rs();
        $pref_type = 'devprof_pref';
        $reseller_id = $item->config->device->reseller_id;
    } else {
        return;
    }

    if ($type eq "subscribers" && grep {/^peer_auth_/} keys %{ $resource }) {
        $c->log->debug("Fetching old peer_auth_params for future comparison");
        NGCP::Panel::Utils::Preferences::get_peer_auth_params(
            $c, $elem, $old_auth_prefs);
    };

    # make sure to not clear any internal prefs, except for those defined
    # in extra:
    my $extra = [qw/
        rewrite_caller_in_dpid rewrite_caller_out_dpid
        rewrite_callee_in_dpid rewrite_callee_out_dpid
        rewrite_caller_lnp_dpid rewrite_callee_lnp_dpid
        ncos_id adm_ncos_id adm_cf_ncos_id
        emergency_mapping_container_id
        sound_set contract_sound_set
        allowed_ips_grp man_allowed_ips_grp
    /];
    $full_rs = $full_rs->search({
        -or => [
            'attribute.internal' => 0,
            'attribute.attribute' => { 'in' => $extra },
        ]
    },{
        join => 'attribute',
    });

    if($replace) {
        # in case of PUT, we remove all old entries
        try {
            $full_rs->delete_all;
        } catch($e) {
            $c->log->error("failed to clear preferences for '$accessor': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        };
    } else {
        # in case of PATCH, we remove only those entries marked for removal in the patch
        try {
            foreach my $k(keys %{ $old_resource }) {
                SWITCH: for ($k) {
                    # no special treatment for *_sound_set deletion, as id is stored in right name
                    /^rewrite_rule_set$/ && do {
                        unless(exists $resource->{$k}) {
                            foreach my $p(qw/
                                caller_in_dpid callee_in_dpid
                                caller_out_dpid callee_out_dpid
                                caller_lnp_dpid callee_lnp_dpid/) {
                                my $rs = $self->get_preference_rs($c, $type, $elem, 'rewrite_' . $p);
                                next unless $rs; # unknown resource, just ignore
                                $rs->delete;
                            }
                        }
                        last SWITCH;
                    };
                    /^(adm_)?(cf_)?ncos$/ && do {
                        unless(exists $resource->{$k}) {
                            my $rs = $self->get_preference_rs($c, $type, $elem, $k . '_id');
                            last SWITCH unless $rs; # unknown resource, just ignore
                            $rs->delete;
                        }
                        last SWITCH;
                    };
                    /^emergency_mapping_container$/ && do {
                        unless(exists $resource->{$k}) {
                            my $rs = $self->get_preference_rs($c, $type, $elem, $k . '_id');
                            last SWITCH unless $rs; # unknown resource, just ignore
                            $rs->delete;
                        }
                        last SWITCH;
                    };
                    /^(man_)?allowed_ips$/ && do {
                        unless(exists $resource->{$k}) {
                            my $rs = $self->get_preference_rs($c, $type, $elem, $k . '_grp');
                            last SWITCH unless $rs; # unknown resource, just ignore
                            if($rs->first) {
                                $c->model('DB')->resultset('voip_allowed_ip_groups')->search({
                                    group_id => $rs->first->value,
                                })->delete;
                            }
                            $rs->delete;
                        }
                        last SWITCH;
                    };
                    # default
                    unless(exists $resource->{$k}) {
                        my $rs = $self->get_preference_rs($c, $type, $elem, $k);
                        last SWITCH unless $rs; # unknown resource, just ignore
                        $rs->delete;
                        if ($type eq "subscribers" && ($k eq 'voicemail_echo_number' || $k eq 'cli')) {
                            NGCP::Panel::Utils::Subscriber::update_voicemail_number(
                                schema => $c->model('DB'), subscriber => $item);
                        }
                    }
                } # SWITCH
            }
        } catch($e) {
            $c->log->error("failed to clear preference for '$accessor': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        };
    }

    foreach my $pref(keys %{ $resource }) {
        next unless(defined $resource->{$pref});
        my $pref_rs = $self->get_preference_rs($c, $type, $elem, $pref);
        unless($pref_rs) {
            $c->log->debug("removing unknown preference '$pref' from update");
            next;
        }
        $pref_rs = $pref_rs->search(undef, {
            order_by => { '-asc' => 'id' },
        });

        # TODO: can't we get this via $pref_rs->search_related or $pref_rs->related_resultset?
        my $meta = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $pref, $pref_type => 1,
        });
        unless($meta) {
            $c->log->error("failed to get voip_preference entry for '$pref'");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        }

        try {
            my $vtype = ref $resource->{$pref};
            my $maxlen = 128;

            if($vtype eq "") {
                if(length($resource->{$pref}) > $maxlen) {
                    $c->log->error("preference '$pref' exceeds maximum length of $maxlen characters");
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Preference '$pref' exceeds maximum length of $maxlen characters");
                    return;
                }
            } elsif($vtype eq "ARRAY") {
                foreach my $a(@{ $resource->{$pref} }) {
                    if(length($a) > $maxlen) {
                        $c->log->error("element in preference '$pref' exceeds maximum length of $maxlen characters");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Element in preference '$pref' exceeds maximum length of $maxlen characters");
                        return;
                    }
                }
            }

            if($meta->data_type eq "boolean" && JSON::is_bool($resource->{$pref})) {
                $vtype = "";
            }
            if($meta->max_occur == 1 && $vtype ne "") {
                $c->log->error("preference '$pref' has max_occur '".$meta->max_occur."', but value got passed in as '$vtype', expected flat value");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid data type '$vtype' for preference '$pref', expected flat value");
                return;
            } elsif($meta->max_occur != 1 && $vtype ne "ARRAY") {
                $c->log->error("preference '$pref' has max_occur '".$meta->max_occur."', but value got passed in as '$vtype', expected ARRAY");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid data type '$vtype' for preference '$pref', expected ARRAY");
                return;
            }

            SWITCH: for ($pref) {
                /^rewrite_rule_set$/ && do {
                    my $rwr_set = $c->model('DB')->resultset('voip_rewrite_rule_sets')->find({
                        name => $resource->{$pref},
                        reseller_id => $reseller_id,
                    });
                    unless($rwr_set) {
                        $c->log->error("no rewrite rule set '".$resource->{$pref}."' for reseller id $reseller_id found");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown rewrite_rule_set '".$resource->{$pref}."'");
                        return;
                    }
                    foreach my $k(qw/
                                    caller_in_dpid callee_in_dpid
                                    caller_out_dpid callee_out_dpid
                                    caller_lnp_dpid callee_lnp_dpid/) {
                        my $rs = $self->get_preference_rs($c, $type, $elem, 'rewrite_'.$k);
                        if($rs->first) {
                            $rs->first->update({ value => $rwr_set->$k });
                        } else {
                            $rs->create({ value => $rwr_set->$k });
                        }
                    }
                    last SWITCH;
                };
                /^(adm_)?(cf_)?ncos$/ && do {
                    my $pref_name = $pref . "_id";
                    my $ncos = $c->model('DB')->resultset('ncos_levels')->find({
                        level => $resource->{$pref},
                        reseller_id => $reseller_id,
                    });
                    unless($ncos) {
                        $c->log->error("no ncos level '".$resource->{$pref}."' for reseller id $reseller_id found");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown ncos_level '".$resource->{$pref}."'");
                        return;
                    }
                    my $rs = $self->get_preference_rs($c, $type, $elem, $pref_name);
                    if($rs->first) {
                        $rs->first->update({ value => $ncos->id });
                    } else {
                        $rs->create({ value => $ncos->id });
                    }
                    last SWITCH;
                };
                /^emergency_mapping_container$/ && do {
                    my $pref_name = $pref . "_id";
                    my $container = $c->model('DB')->resultset('emergency_containers')->find({
                        name => $resource->{$pref},
                        reseller_id => $reseller_id,
                    });
                    unless($container) {
                        $c->log->error("no emergency mapping container '".$resource->{$pref}."' for reseller id $reseller_id found");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown emergency mapping container '".$resource->{$pref}."'");
                        return;
                    }
                    my $rs = $self->get_preference_rs($c, $type, $elem, $pref_name);
                    if($rs->first) {
                        $rs->first->update({ value => $container->id });
                    } else {
                        $rs->create({ value => $container->id });
                    }
                    last SWITCH;
                };
                /^(contract_)?sound_set$/ && do {
                    # TODO: not applicable for domains, but for subs, check for contract_id!
                    my $set = $c->model('DB')->resultset('voip_sound_sets')->find({
                        name => $resource->{$pref},
                        reseller_id => $reseller_id,
                    });
                    unless($set) {
                        $c->log->error("no $pref '".$resource->{$pref}."' for reseller id $reseller_id found");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown $pref '".$resource->{$pref}."'");
                        return;
                    }
                    my $rs = $self->get_preference_rs($c, $type, $elem, $pref);
                    if($rs->first) {
                        $rs->first->update({ value => $set->id });
                    } else {
                        $rs->create({ value => $set->id });
                    }
                    last SWITCH;
                };
                /^(man_)?allowed_ips$/ && do {
                    my $pref_name = $pref . "_grp";
                    my $aig_rs;
                    my $aig_group_id;
                    my $rs = $self->get_preference_rs($c, $type, $elem, $pref_name);
                    if($rs->first) {
                        $aig_group_id = $rs->first->value;
                        $aig_rs = $c->model('DB')->resultset('voip_allowed_ip_groups')->search({
                            group_id => $aig_group_id
                        });
                        $aig_rs->delete;
                    } else {
                        my $new_group = $c->model('DB')->resultset('voip_aig_sequence')->create({});
                        $aig_group_id = $new_group->id;
                        $aig_rs = $c->model('DB')->resultset('voip_allowed_ip_groups')->search({
                            group_id => $aig_group_id
                        });
                        $c->model('DB')->resultset('voip_aig_sequence')->search_rs({
                                id => { '<' => $aig_group_id },
                            })->delete_all;
                    }
                    foreach my $ip(@{ $resource->{$pref} }) {
                        unless($self->validate_ipnet($c, $pref, $ip)) {
                            $c->log->error("invalid $pref entry '$ip'");
                            return;
                        }
                        $aig_rs->create({ ipnet => $ip });
                    }
                    unless($rs->first) {
                        $rs->create({ value => $aig_group_id });
                    }
                    # in contrast to panel, it does not drop the allowed_ips_grp pref, if empty ipnets.
                    last SWITCH;
                };
                # default
                if($meta->max_occur != 1) {
                    $pref_rs->delete;
                    foreach my $v(@{ $resource->{$pref} }) {
                        return unless $self->check_pref_value($c, $meta, $v, $pref_type);
						if(JSON::is_bool($v)){
							$v =  $v ? 1 : 0 ;
						}
                        $pref_rs->create({ value => $v });
                    }
                } elsif($pref_rs->first) {
                    return unless $self->check_pref_value($c, $meta, $resource->{$pref}, $pref_type);
                    if(JSON::is_bool($resource->{$pref})){
						$resource->{$pref} =  $resource->{$pref} ? 1 : 0 ;
					}
                    $pref_rs->first->update({ value => $resource->{$pref} });
                } else {
                    return unless $self->check_pref_value($c, $meta, $resource->{$pref}, $pref_type);
                    if(JSON::is_bool($resource->{$pref})){
						$resource->{$pref} =  $resource->{$pref} ? 1 : 0 ;
					}
                    $pref_rs->create({ value => $resource->{$pref} });
                }
            } # SWITCH
            if ($type eq "subscribers" && ($pref eq 'voicemail_echo_number' || $pref eq 'cli')) {
                NGCP::Panel::Utils::Subscriber::update_voicemail_number(
                    schema => $c->model('DB'), subscriber => $item);
            }
        } catch($e) {
            $c->log->error("failed to update preference for '$accessor': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        }
    }

    if($type eq "subscribers") {
        if(keys %{ $old_auth_prefs }) {
            my $new_auth_prefs = {};
            my $prov_subscriber = $elem;
            NGCP::Panel::Utils::Preferences::get_peer_auth_params(
                $c, $prov_subscriber, $new_auth_prefs);
            unless(compare($old_auth_prefs, $new_auth_prefs)) {
                $c->log->debug("peer_auth_params changed. Updating sems.");
                try {
                    NGCP::Panel::Utils::Preferences::update_sems_peer_auth(
                        $c, $prov_subscriber, $old_auth_prefs, $new_auth_prefs);
                } catch($e) {
                    $c->log->error("Failed to set peer registration: $e");
                    $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error."); # TODO?
                    return;
                }
            }
        }
    }

    return $item;
}

sub check_pref_value {
    my ($self, $c, $meta, $value, $pref_type) = @_;
    my $err;

    my $vtype = ref $value;
    if($meta->data_type eq "boolean" && JSON::is_bool($value)) {
        $vtype = "";
    }
    unless($vtype eq "") {
        $c->log->error("preference '".$meta->attribute."' has invalid value data structure, expected plain value");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid data structure as value for element in preference '".$meta->attribute."', expected plain value");
        return;
    }

    SWITCH: for ($meta->data_type) {
        /^int$/ && do {
            $err = 1 unless is_int($value);
            last SWITCH;
        };
        /^boolean$/ && do {
            $err = 1 unless JSON::is_bool($value);
            last SWITCH;
        };
        # default
    } # SWITCH
    if($err) {
        $c->log->error("preference '".$meta->attribute."' has invalid value data type, expected '".$meta->data_type."'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid data type for element in preference '".$meta->attribute."', expected '".$meta->data_type."'");
        return;
    }

    if($meta->data_type eq "enum") {
        my $enum = $c->model('DB')->resultset('voip_preferences_enum')->find({
            preference_id => $meta->id,
            $pref_type => 1,
            value => $value,
        });
        unless($enum) {
            $c->log->error("preference '".$meta->attribute."' has invalid enum value '".$value."'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid enum value in preference '".$meta->attribute."'");
            return;
        }
    }

    return 1;
}

sub validate_ipnet {
    my ($self, $c, $pref, $ipnet) = @_;
    my ($ip, $net) = split /\//, $ipnet;
    if(is_ipv4($ip)) {
        return 1 unless(defined $net);
        unless(is_int($net) && $net >= 0 && $net <= 32) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv4 network portion in $pref entry '$ipnet', must be 0 <= net <= 32");
            return;
        }
    } elsif(is_ipv6($ip)) {
        return 1 unless(defined $net);
        unless(is_int($net) && $net >= 0 && $net <= 128) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv6 network portion in $pref entry '$ipnet', must be 0 <= net <= 128");
            return;
        }
    } else {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv4 or IPv6 address in $pref entry '$ipnet', must be valid address with optional /net suffix");
        return;
    }
    return 1;
}

1;
# vim: set tabstop=4 expandtab:
