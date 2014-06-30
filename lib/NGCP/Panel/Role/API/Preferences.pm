package NGCP::Panel::Role::API::Preferences;
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
use Safe::Isa qw($_isa);
use Data::Validate::IP qw/is_ipv4 is_ipv6/;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;

sub get_form {
    my ($self, $c) = @_;
    return;
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;

    my $print_type = $type;
    $print_type = "customers" if $print_type eq "contracts";
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
            Data::HAL::Link->new(relation => "ngcp:$print_type", href => sprintf("/api/%s/%d", $print_type, $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->get_resource($c, $item, $type);
    $hal->resource($resource);
    return $hal;
}

sub get_resource {
    my ($self, $c, $item, $type) = @_;

    my $prefs;
    if($type eq "subscribers") {
        $prefs = $item->provisioning_voip_subscriber->voip_usr_preferences;
    } elsif($type eq "domains") {
        $prefs = $item->provisioning_voip_domain->voip_dom_preferences;
    } elsif($type eq "peerings") {
        $prefs = $item->voip_peer_preferences;
    } elsif($type eq "contracts") {
        $prefs = $item->voip_contract_preferences;
    }
    $prefs = $prefs->search({
    }, {
        join => 'attribute',
        order_by => { '-asc' => 'id' },
    });

    my $resource;
    foreach my $pref($prefs->all) {
        my $value;

        given($pref->attribute->attribute) {
            when(/^rewrite_calle[re]_(in|out)_dpid$/) {
                next if(exists $resource->{rewrite_rule_set});
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
                next;
                # TODO: HAL link to rewrite rule set? Also/instead set id?
            }

            when(/^(adm_)?ncos_id$/) {
                my $pref_name = $pref->attribute->attribute;
                $pref_name =~ s/_id$//;
                my $ncos = $c->model('DB')->resultset('ncos_levels')->find({
                    id => $pref->value,
                });
                if($ncos) {
                    $resource->{$pref_name} = $ncos->level;
                } else {
                    $c->log->error("no ncos level for '".$pref->attribute->attribute."' with value '".$pref->value."' found, altough it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                next;
                # TODO: HAL link to rewrite rule set? Also/instead set id?
            }

            when(/^(contract_)?sound_set$/) {
                # TODO: not applicable for domains, but for subs, check for contract_id!
                my $set = $c->model('DB')->resultset('voip_sound_sets')->find({
                    id => $pref->value,
                });
                if($set) {
                    $resource->{$pref->attribute->attribute} = $set->name;
                } else {
                    $c->log->error("no sound set for '".$pref->attribute->attribute."' with value '".$pref->value."' found, altough it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                next;
                # TODO: HAL link to rewrite rule set? Also/instead set id?
            }

            when(/^(man_)?allowed_ips_grp$/) {
                my $pref_name = $pref->attribute->attribute;
                $pref_name =~ s/_grp$//;
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
                next;
            }

            default { 
                if($pref->attribute->internal != 0) {
                    next;
                }
            }

        }

        
        given($pref->attribute->data_type) {
            when("int")     { $value = int($pref->value) if($pref->value->is_int) }
            when("boolean") { $value = JSON::Types::bool($pref->value) if(defined $pref->value) }
            default         { $value = $pref->value }
        }
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
    } elsif($type eq "peerings") {
        $resource->{peering_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "contracts") {
        $resource->{customer_id} = int($item->id);
        $resource->{id} = int($item->id);
    }

    return $resource;
}

sub item_rs {
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
    } elsif($type eq "subscribers") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('voip_subscribers')
                ->search({ status => { '!=' => 'terminated' } });
        } elsif($c->user->roles eq "reseller") {
            $item_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'contact.reseller_id' => $c->user->reseller_id,
                'status' => { '!=' => 'terminated' },
            }, {
                join => { 'contract' => 'contact' },
            });
        }
    } elsif($type eq "peerings") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('voip_peer_hosts');
        } else {
            return;
        }
    } elsif($type eq "contracts") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('contracts')->search({ 
                status => { '!=' => 'terminated' },
                'contact.reseller_id' => { '!=' => undef },

            },{
                join => 'contact',
            });
        } elsif($c->user->roles eq "reseller") {
            $item_rs = $c->model('DB')->resultset('contracts')->search({
                'contact.reseller_id' => $c->user->reseller_id,
                'status' => { '!=' => 'terminated' },
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
    } elsif($type eq "subscribers") {
        $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c,
            attribute => $attr,
            prov_subscriber => $elem,
        );
    } elsif($type eq "peerings") {
        $rs = NGCP::Panel::Utils::Preferences::get_peer_preference_rs(
            c => $c,
            attribute => $attr,
            peer_host => $elem,
        );
    } elsif($type eq "contracts") {
        $rs = NGCP::Panel::Utils::Preferences::get_contract_preference_rs(
            c => $c,
            attribute => $attr,
            contract => $elem,
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
    } elsif($type eq "subscribers") {
        delete $resource->{subscriber_id};
        delete $resource->{subscriberpreferences_id};
        delete $old_resource->{subscriber_id};
        delete $old_resource->{subscriberpreferences_id};
        $accessor = $item->username . '@' . $item->domain->domain;
        $elem = $item->provisioning_voip_subscriber;
        $full_rs = $elem->voip_usr_preferences;
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
        $accessor = $item->id;
        $elem = $item;
        $full_rs = $elem->voip_contract_preferences;
        $pref_type = 'contract_pref';
        $reseller_id = $item->contact->reseller_id;
    } else {
        return;
    }

    # make sure to not clear any internal prefs, except for those defined
    # in extra:
    my $extra = [qw/
        rewrite_caller_in_dpid rewrite_caller_out_dpid 
        rewrite_callee_in_dpid rewrite_callee_out_dpid 
        ncos_id adm_ncos_id 
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
                given($k) {

                    # no special treatment for *_sound_set deletion, as id is stored in right name
                    when(/^rewrite_rule_set$/) {
                        unless(exists $resource->{$k}) {
                            foreach my $p(qw/caller_in_dpid callee_in_dpid caller_out_dpid callee_out_dpid/) {
                                my $rs = $self->get_preference_rs($c, $type, $elem, 'rewrite_' . $p);
                                next unless $rs; # unknown resource, just ignore
                                $rs->delete;
                            }
                        }
                    }
                    when(/^(adm_)?ncos$/) {
                        unless(exists $resource->{$k}) {
                            my $rs = $self->get_preference_rs($c, $type, $elem, $k . '_id');
                            next unless $rs; # unknown resource, just ignore
                            $rs->delete;
                        }
                    }
                    when(/^(man_)?allowed_ips$/) {
                        unless(exists $resource->{$k}) {
                            my $rs = $self->get_preference_rs($c, $type, $elem, $k . '_grp');
                            next unless $rs; # unknown resource, just ignore
                            if($rs->first) {
                                $c->model('DB')->resultset('voip_allowed_ip_groups')->search({
                                    group_id => $rs->first->value,
                                })->delete;
                            }
                            $rs->delete;
                        }
                    }
                    default {
                        unless(exists $resource->{$k}) {
                            my $rs = $self->get_preference_rs($c, $type, $elem, $k);
                            next unless $rs; # unknown resource, just ignore
                            $rs->delete;
                        }
                    }
                }
            }
        } catch($e) {
            $c->log->error("failed to clear preference for '$accessor': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        };
    }

    foreach my $pref(keys %{ $resource }) {
        next unless(defined $resource->{$pref});
        my $rs = $self->get_preference_rs($c, $type, $elem, $pref);
        unless($rs) {
            $c->log->debug("removing unknown preference '$pref' from update");
            next;
        }
        $rs = $rs->search(undef, {
            order_by => { '-asc' => 'id' },
        });

        # TODO: can't we get this via $rs->search_related or $rs->related_resultset?
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

            given($pref) {
                when(/^rewrite_rule_set$/) {

                    my $rwr_set = $c->model('DB')->resultset('voip_rewrite_rule_sets')->find({
                        name => $resource->{$pref},
                        reseller_id => $reseller_id,
                    });
                    
                    unless($rwr_set) {
                        $c->log->error("no rewrite rule set '".$resource->{$pref}."' for reseller id $reseller_id found");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown rewrite_rule_set '".$resource->{$pref}."'");
                        return;
                    }

                    foreach my $k(qw/caller_in_dpid callee_in_dpid caller_out_dpid callee_out_dpid/) {
                        my $rs = $self->get_preference_rs($c, $type, $elem, 'rewrite_'.$k);
                        if($rs->first) {
                            $rs->first->update({ value => $rwr_set->$k });
                        } else {
                            $rs->create({ value => $rwr_set->$k });
                        }
                    }
                }

                when(/^(adm_)?ncos$/) {
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
                }

                when(/^(contract_)?sound_set$/) {
                    # TODO: not applicable for domains, but for subs, check for contract_id!
                    my $set = $c->model('DB')->resultset('voip_sound_sets')->find({
                        name => $resource->{$pref},
                        reseller_id => $reseller_id,
                    });
                    unless($set) {
                        $c->log->error("no $pref '".$resource->{$pref}."' for reseller id $reseller_id found");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown $pref'".$resource->{$pref}."'");
                        return;
                    }
                    my $rs = $self->get_preference_rs($c, $type, $elem, $pref);
                    if($rs->first) {
                        $rs->first->update({ value => $set->id });
                    } else {
                        $rs->create({ value => $set->id });
                    }
                }

                when(/^(man_)?allowed_ips$/) {
                    my $pref_name = $pref . "_grp";
                    my $aig_rs;
                    my $seq;
                    my $rs = $self->get_preference_rs($c, $type, $elem, $pref_name);
                    if($rs->first) {
                        $aig_rs = $c->model('DB')->resultset('voip_allowed_ip_groups')->search({
                            group_id => $rs->first->value
                        });
                        $aig_rs->delete;
                    } else {
                        my $aig_seq = $c->model('DB')->resultset('voip_aig_sequence')->search({},{
                            for => 'update',
                        });
                        unless($aig_seq->first) {
                            $seq = 1;
                            $aig_seq->create({ id => $seq });
                        } else {
                            $seq = $aig_seq->first->id + 1;
                            $aig_seq->first->update({ id => $seq });
                        }
                        $aig_rs = $c->model('DB')->resultset('voip_allowed_ip_groups')->search({
                            group_id => $seq
                        });
                    }

                    foreach my $ip(@{ $resource->{$pref} }) {
                        unless($self->validate_ipnet($c, $pref, $ip)) {
                            $c->log->error("invalid $pref entry '$ip'");
                            return;
                        }
                        $aig_rs->create({ ipnet => $ip });
                    }

                    unless($rs->first) {
                        $rs->create({ value => $seq });
                    }
                }

                default {

                    if($meta->max_occur != 1) {
                        $rs->delete;
                        foreach my $v(@{ $resource->{$pref} }) {
                            return unless $self->check_pref_value($c, $meta, $v, $pref_type);
                            $rs->create({ value => $v });
                        }
                    } elsif($rs->first) {
                        return unless $self->check_pref_value($c, $meta, $resource->{$pref}, $pref_type);
                        $resource->{$pref} = (!! $resource->{$pref}) if JSON::is_bool($resource->{$pref});
                        $rs->first->update({ value => $resource->{$pref} });
                    } else {
                        return unless $self->check_pref_value($c, $meta, $resource->{$pref}, $pref_type);
                        $resource->{$pref} = (!! $resource->{$pref}) if JSON::is_bool($resource->{$pref});
                        $rs->create({ value => $resource->{$pref} });
                    }
                }
            }
        } catch($e) {
            $c->log->error("failed to update preference for '$accessor': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
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

    given($meta->data_type) {
        when("int") { $err = 1 unless $value->is_int }
        when("boolean") { $err = 1 unless JSON::is_bool($value) }
    }
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
        unless($net->is_int && $net >= 0 && $net <= 32) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv4 network portion in $pref entry '$ipnet', must be 0 <= net <= 32");
            return;
        }
    } elsif(is_ipv6($ip)) {
        return 1 unless(defined $net);
        unless($net->is_int && $net >= 0 && $net <= 128) {
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
