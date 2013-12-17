package NGCP::Panel::Role::API::DomainPreferences;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "api_admin") {
        return NGCP::Panel::Form::Domain::Admin->new;
    } elsif($c->user->roles eq "api_reseller") {
        return NGCP::Panel::Form::Domain::Reseller->new;
    }
    return;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

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
            Data::HAL::Link->new(relation => 'ngcp:domains', href => sprintf("/api/domains/%d", $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->get_resource($c, $item);
    $hal->resource($resource);
    return $hal;
}

sub get_resource {
    my ($self, $c, $item) = @_;

    my $prefs = $item->provisioning_voip_domain->voip_dom_preferences->search({
    }, {
        join => 'attribute'
    });

    my $resource;
    foreach my $pref($prefs->all) {
        my $value;

        given($pref->attribute->attribute) {
            $c->log->debug("+++++++++++++ checking preference ".$pref->attribute->attribute);
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

            when(/^(adm_)?sound_set$/) {
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
                });
                foreach my $set($sets->all) {
                    $resource->{$pref_name} = []
                        unless exists($resource->{$pref_name});
                    push @{ $resource->{$pref_name} }, $set->ipnet;
                }
                next;
            }

            default { next if $pref->attribute->internal != 0 }

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
    $resource->{domain_id} = int($item->id);
    $resource->{domainpreferences_id} = int($item->id);
    return $resource;
}

sub item_rs {
    my ($self, $c) = @_;

    # we actually return the domain rs here, as we can easily
    # go to dom_preferences from there
    my $item_rs;
    if($c->user->roles eq "api_admin") {
        $item_rs = $c->model('DB')->resultset('domains');
    } elsif($c->user->roles eq "api_reseller") {
        $item_rs = $c->model('DB')->resultset('admins')->find(
                { id => $c->user->id, } )
            ->reseller
            ->domain_resellers
            ->search_related('domain');
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $replace) = @_;

    delete $resource->{id};
    delete $resource->{domain_id};
    delete $resource->{domainpreferences_id};

    if($replace) {
        # in case of PUT, we remove all old entries
        try {
            $item->provisioning_voip_domain->voip_dom_preferences->delete_all;
        } catch($e) {
            $c->log->error("failed to clear preferences for domain '".$item->domain."': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        };
    } else {
        # in case of PATCH, we remove only those entries marked for removal in the patch
        try {
            foreach my $k(keys %{ $old_resource }) {
                unless(exists $resource->{$k}) {
                    my $rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                        c => $c,
                        attribute => $k,
                        prov_domain => $item->provisioning_voip_domain,
                    );
                    next unless $rs; # unknown resource, just ignore
                    $rs->delete_all;
                }
            }
        } catch($e) {
            $c->log->error("failed to clear preference for domain '".$item->domain."': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        };
    }

    foreach my $pref(keys %{ $resource }) {
        next unless(defined $resource->{$pref});
        my $rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
            c => $c,
            attribute => $pref,
            prov_domain => $item->provisioning_voip_domain,
        );
        unless($rs) {
            $c->log->debug("removing unknown dom_preference '$pref' from update");
            next;
        }

        # TODO: can't we get this via $rs->search_related or $rs->related_resultset?
        my $meta = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $pref, 'dom_pref' => 1,
        });
        unless($meta) {
            $c->log->error("failed to get voip_preference entry for '$pref'");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        }

        # TODO: special handling for different prefs (sound set, rewrite rule etc)
        # TODO: check for valid enum values below!

        try {
            my $vtype = ref $resource->{$pref};
            if($meta->max_occur == 1 && $vtype ne "") {
                $c->log->error("preference '$pref' has max_occur '".$meta->max_occur."', but value got passed in as '$vtype', expected flat value");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid data type '$vtype' for preference '$pref', expected flat value");
                return;
            } elsif($meta->max_occur != 1 && $vtype ne "ARRAY") {
                $c->log->error("preference '$pref' has max_occur '".$meta->max_occur."', but value got passed in as '$vtype', expected ARRAY");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid data type '$vtype' for preference '$pref', expected ARRAY");
                return;
            }

            if($meta->max_occur != 1) {
                $rs->delete_all;
                foreach my $v(@{ $resource->{$pref} }) {
                    return unless $self->check_pref_value($c, $meta, $v);
                    $rs->create({ value => $v });
                }
            } elsif($rs->first) {
                return unless $self->check_pref_value($c, $meta, $resource->{$pref});
                $rs->first->update({ value => $resource->{$pref} });
            } else {
                return unless $self->check_pref_value($c, $meta, $resource->{$pref});
                $rs->create({ value => $resource->{$pref} });
            }
        } catch($e) {
            $c->log->error("failed to update preference for domain '".$item->domain."': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        }
    }

    return $item;
}

# TODO: check for valid ENUM values!
sub check_pref_value {
    my ($self, $c, $meta, $value) = @_;
    my $err;

    my $vtype = ref $value;
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

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
