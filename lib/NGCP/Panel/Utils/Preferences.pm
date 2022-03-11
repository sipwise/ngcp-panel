package NGCP::Panel::Utils::Preferences;

use Sipwise::Base;

use Data::Validate::IP qw/is_ipv4 is_ipv6/;
use NGCP::Panel::Form::Preferences;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::I18N qw//;
use NGCP::Panel::Utils::Sems;
use JSON qw();
use HTTP::Status qw(:constants);
use File::Type;
use Readonly;
use MIME::Base64 qw(decode_base64);

use constant _DYNAMIC_PREFERENCE_PREFIX => '__';

our $TYPE_PREF_MAP = {
    'domains'           => 'dom',
    'profiles'          => 'prof',
    'subscribers'       => 'usr',
    'peerings'          => 'peer',
    'resellers'         => 'reseller',
    'pbxdevicemodels'   => 'dev',
    'pbxdeviceprofiles' => 'devprof',
    'pbxdevices'        => 'fielddev',
    'contracts'         => 'contract',
};

my $API_TRANSFORM_OUT;
my $API_TRANSFORM_IN;
my $CODE_SUFFIX_FNAME = '_code';
Readonly my $blob_short_value_size => 4096;

sub validate_ipnet {
    my ($field) = @_;
    if ( !$field->value ) {
        $field->add_error("Invalid IPv4 or IPv6 address, must be valid address with optional /net suffix.");
        return;
    }
    return _validate_ipnet(undef, $field->value, sub {
        my ($code, $msg) = @_;
        $field->add_error($msg);
    });
}

sub _validate_ipnet {
    my ($pref, $ipnet, $err_code) = @_;
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { };
    }
    my ($ip, $net) = split /\//, $ipnet;
    if(is_ipv4($ip)) {
        return 1 unless(defined $net);
        unless(is_int($net) && $net >= 0 && $net <= 32) {
            &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv4 network portion in $pref entry '$ipnet', must be 0 <= net <= 32") if $pref;
            &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv4 network portion, must be 0 <= net <= 32") unless $pref;
            return;
        }
    } elsif(is_ipv6($ip)) {
        return 1 unless(defined $net);
        unless(is_int($net) && $net >= 0 && $net <= 128) {
            &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv6 network portion in $pref entry '$ipnet', must be 0 <= net <= 128") if $pref;
            &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv6 network portion, must be 0 <= net <= 128") unless $pref;
            return;
        }
    } else {
        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv4 or IPv6 address in $pref entry '$ipnet', must be valid address with optional /net suffix") if $pref;
        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid IPv4 or IPv6 address, must be valid address with optional /net suffix") unless $pref;
        return;
    }
    return 1;
}

sub prepare_resource {

    my %params = @_;

    my ($c,
        $schema,
        $item,
        $type) = @params{qw/
        c
        schema
        item
        type
    /};

    my $prefs;
    my $blob_rs;
    my %profile_attrs = (); # for filtering profiles based list
    my %profile_allowed_attrs; # for filtering subscriber attrs on its profile
    my $has_profile = 0;
    my $attr = 0;
    if($type eq "subscribers") {
        $prefs = $item->provisioning_voip_subscriber->voip_usr_preferences;
        $blob_rs = $c->model('DB')->resultset('voip_usr_preferences_blob');
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
        $blob_rs = $c->model('DB')->resultset('voip_dom_preferences_blob');
    } elsif($type eq "peerings") {
        $prefs = $item->voip_peer_preferences;
        $blob_rs = $c->model('DB')->resultset('voip_peer_preferences_blob');
    } elsif($type eq "resellers") {
        $prefs = $item->reseller_preferences;
    } elsif($type eq "contracts") {
        $prefs = $item->voip_contract_preferences->search(
                    { location_id => $c->request->param('location_id') || undef },
                    undef);
        $blob_rs = $c->model('DB')->resultset('voip_contract_preferences_blob');
    } elsif($type eq "pbxdevicemodels") {
        $prefs = $item->voip_dev_preferences;
    } elsif($type eq "pbxdeviceprofiles") {
        $prefs = $item->voip_devprof_preferences;
    } elsif($type eq "pbxdevices") {
        $prefs = $item->voip_fielddev_preferences;
    } elsif($type eq "active") {
        my $sub_prefs = $item->provisioning_voip_subscriber->voip_usr_preferences->search(undef, {columns => ['value', 'attribute_id']});
        my $profile = $item->provisioning_voip_subscriber->voip_subscriber_profile;
        if ($profile) {
            $has_profile = 1;
            %profile_allowed_attrs = map { $_ => 1 } $profile->profile_attributes->get_column('attribute_id')->all;
        }
        my $dom_prefs = $item->domain->provisioning_voip_domain->voip_dom_preferences->search(
            undef,
            {
                columns => ['value', 'attribute_id'],
                result_class => $sub_prefs->result_class
            }
        );
        #search for location if IP is provided
        my $location_id;
        if ($c->request->param('location_ip')) {
            my $location = $schema->resultset('voip_contract_locations')->search(
                {
                    'voip_contract_location_blocks.ip' => $c->request->param('location_ip')
                },
                {
                    join => 'voip_contract_location_blocks'
                }
            )->first;
            $location_id = $location->id if ($location);
        }
        my $ct_prefs = $item->contract->voip_contract_preferences->search(
            {
                location_id => $location_id || undef
            },
            {
                columns => ['value', 'attribute_id'],
                result_class => $sub_prefs->result_class
            }
        );

        $prefs = $sub_prefs->union($ct_prefs->search({attribute_id => {-not_in => [map {$_->get_column('attribute_id')} $sub_prefs->all]}}));
        $prefs = $prefs->union($dom_prefs->search({attribute_id => {-not_in => [map {$_->get_column('attribute_id')} $prefs->all]}}));
    }

    $prefs = $prefs->search({
    }, {
        prefetch => 'attribute',
        order_by => { '-asc' => 'me.id' },
    });

    my $resource;
    foreach my $pref($prefs->all) {
        my $value;
        my $processed = 0;

        if ($c->user->roles eq 'subscriberadmin' || $c->user->roles eq 'subscriber') {
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
                    if($attr && !_check_profile($c, 'rewrite_rule_set', \%profile_attrs));
                my $col = $pref->attribute->attribute;
                $col =~ s/^rewrite_//;
                my $rwr_set = $schema->resultset('voip_rewrite_rule_sets')->find({
                    $col => $pref->value,
                });
                if($rwr_set) {
                    $resource->{rewrite_rule_set} = $rwr_set->name;
                } else {
                    $c->log->error("no rewrite rule set for '".$pref->attribute->attribute."' with value '".$pref->value."' found, although it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                $processed = 1;
                last SWITCH;
            };
            /^cdr_export_sclidui_rwrs_id$/ && do {
                my $pref_name = $pref->attribute->attribute;
                $pref_name =~ s/_id$//;
                my $rwr_set = $schema->resultset('voip_rewrite_rule_sets')->find({
                    id => $pref->value,
                });
                if($rwr_set) {
                    $resource->{$pref_name} = $rwr_set->name;
                } else {
                    $c->log->error("no rewrite rule set for '".$pref->attribute->attribute."' with value '".$pref->value."' found, although it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                $processed = 1;
                last SWITCH;
            };
            /^(adm_)?(cf_)?ncos_id$/ && do {
                my $pref_name = $pref->attribute->attribute;
                $pref_name =~ s/_id$//;

                do { $processed = 1; last SWITCH; }
                    if($attr && !_check_profile($c, $pref_name, \%profile_attrs));

                my $ncos = $schema->resultset('ncos_levels')->find({
                    id => $pref->value,
                });
                if($ncos) {
                    $resource->{$pref_name} = $ncos->level;
                } else {
                    $c->log->error("no ncos level for '".$pref->attribute->attribute."' with value '".$pref->value."' found, although it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                $processed = 1;
                last SWITCH;
            };
            /^emergency_mapping_container_id$/ && do {
                my $pref_name = $pref->attribute->attribute;
                $pref_name =~ s/_id$//;

                do { $processed = 1; last SWITCH; }
                    if($attr && !_check_profile($c, $pref_name, \%profile_attrs));

                my $container = $schema->resultset('emergency_containers')->find({
                    id => $pref->value,
                });
                if($container) {
                    $resource->{$pref_name} = $container->name;
                } else {
                    $c->log->error("no emergency mapping container for '".$pref->attribute->attribute."' with value '".$pref->value."' found, although it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                $processed = 1;
                last SWITCH;
            };
            /^(contract_)?sound_set$/ && do {
                # TODO: not applicable for domains, but for subs, check for contract_id!
                do { $processed = 1; last SWITCH; }
                    if($attr && !_check_profile($c, $_, \%profile_attrs));

                my $set = $schema->resultset('voip_sound_sets')->find({
                    id => $pref->value,
                });
                if($set) {
                    $resource->{$pref->attribute->attribute} = $set->name;
                } else {
                    $c->log->error("no sound set for '".$pref->attribute->attribute."' with value '".$pref->value."' found, although it's stored in preference id ".$pref->id);
                    # let it slip through
                }
                $processed = 1;
                last SWITCH;
            };
            /^(man_)?allowed_ips_grp$/ && do {
                my $pref_name = $pref->attribute->attribute;
                $pref_name =~ s/_grp$//;
                do { $processed = 1; last SWITCH; }
                    if($attr && !_check_profile($c, $pref_name, \%profile_attrs));
                my $sets = $schema->resultset('voip_allowed_ip_groups')->search({
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
            /^header_rule_set$/ && do {
                my $hrs = $schema->resultset('voip_header_rule_sets')->find({
                    id => $pref->value,
                });
                if($hrs) {
                    $resource->{$pref->attribute->attribute} = $hrs->name;
                } else {
                    $c->log->error("no header rule set for '".$pref->attribute->attribute."' with value '".$pref->value."' found, although it's stored in preference id ".$pref->id);
                    # let it slip through
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
            /^blob$/ && do {
                if (defined $pref->value) {
                    my $blob = $blob_rs->search({ preference_id => $pref->id });
                    my $attribute = $pref->attribute->attribute;
                    if ($c->req->param('preference') && $c->req->param('preference') eq $attribute) {
                        my $data = $blob->first->value;
                        my $ft = File::Type->new();
                        $c->response->header('Content-Disposition' => 'attachment; filename="' . $blob->first->id . '-' . $attribute . '"');
                        $c->response->content_type($ft->mime_type($blob->first->value) || $blob->first->content_type);
                        $c->response->body($data);
                        $c->detach();
                        return 1;
                    }
                    $value = {
                        content_type => $blob->first->content_type,
                        data => $blob->first->value ? '#blob' : undef
                    };
                }
                last SWITCH;
            };
            # default
            $value = $pref->value;
        } # SWITCH
        eval {
            $value = _api_transform_out($c, $pref->attribute, $value);
        };
        if ($@) {
            $c->log->error("Failed to transform pref value - $@");
            # let it slip through
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
    } elsif($type eq "profiles") {
        $resource->{profile_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "peerings") {
        $resource->{peering_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "resellers") {
        $resource->{reseller_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "pbxdevicemodels") {
        $resource->{device_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "pbxdeviceprofiles") {
        $resource->{profile_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "pbxdevices") {
        $resource->{device_id} = int($item->id);
        $resource->{id} = int($item->id);
    } elsif($type eq "contracts") {
        $resource->{customer_id} = int($item->id);
        $resource->{id} = int($item->id);
        $prefs->first ? $resource->{location_id} = $prefs->first->location_id
                      : undef;
    }

    return $resource;
}

sub update_preferences {

    my %params = @_;

    my ($c,
        $schema,
        $item,
        $old_resource,
        $resource,
        $type,
        $replace,
        $err_code) = @params{qw/
        c
        schema
        item
        old_resource
        resource
        type
        replace
        err_code
    /};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { };
    }

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
        $reseller_id = $item->reseller_id;
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
        if ($c->user->roles eq 'subscriberadmin' || $c->user->roles eq 'subscriber') {
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
    } elsif($type eq "resellers") {
        delete $resource->{reseller_id};
        delete $resource->{resellerpreferences_id};
        delete $old_resource->{reseller_id};
        delete $old_resource->{resellerpreferences_id};
        $accessor = $item->name;
        $elem = $item;
        $full_rs = $elem->reseller_preferences;
        $pref_type = 'reseller_pref';
        $reseller_id = $item->id;
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
        delete $old_resource->{profile_id};
        delete $resource->{pbxdeviceprofilepreferences_id};
        delete $old_resource->{pbxdeviceprofilepreferences_id};
        $accessor = $item->id;
        $elem = $item;
        $full_rs = $elem->voip_devprof_preferences->search_rs();
        $pref_type = 'devprof_pref';
        $reseller_id = $item->config->device->reseller_id;
    } elsif($type eq "pbxdevices") {
        delete $resource->{device_id};
        delete $old_resource->{device_id};
        delete $resource->{pbxfielddevicepreferences_id};
        delete $old_resource->{pbxfielddevicepreferences_id};
        $accessor = $item->id;
        $elem = $item;
        $full_rs = $elem->voip_fielddev_preferences->search_rs();
        $pref_type = 'fielddev_pref';
        $reseller_id = $item->profile->config->device->reseller_id;
    } else {
        return;
    }

    if ($type eq "subscribers" && grep {/^peer_auth_/} keys %{ $resource }) {
        $c->log->debug("Fetching old peer_auth_params for future comparison");
        get_peer_auth_params(
            $c, $elem, $old_auth_prefs);
    };

    # make sure to not clear any internal prefs, except for those defined
    # in extra:
    my $extra = [qw/
        rewrite_caller_in_dpid rewrite_caller_out_dpid
        rewrite_callee_in_dpid rewrite_callee_out_dpid
        rewrite_caller_lnp_dpid rewrite_callee_lnp_dpid
        cdr_export_sclidui_rwrs_id
        ncos_id adm_ncos_id adm_cf_ncos_id
        emergency_mapping_container_id
        sound_set contract_sound_set
        allowed_ips_grp man_allowed_ips_grp
        header_rule_set
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
            &$err_code(HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
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
                                my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, 'rewrite_' . $p);
                                next unless $rs; # unknown resource, just ignore
                                $rs->delete;
                            }
                        }
                        last SWITCH;
                    };
                    /^cdr_export_sclidui_rwrs/ && do {
                        unless(exists $resource->{$k}) {
                            my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $k . '_id');
                            last SWITCH unless $rs; # unknown resource, just ignore
                            $rs->delete;
                        }
                        last SWITCH;
                    };
                    /^(adm_)?(cf_)?ncos$/ && do {
                        unless(exists $resource->{$k}) {
                            my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $k . '_id');
                            last SWITCH unless $rs; # unknown resource, just ignore
                            $rs->delete;
                        }
                        last SWITCH;
                    };
                    /^emergency_mapping_container$/ && do {
                        unless(exists $resource->{$k}) {
                            my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $k . '_id');
                            last SWITCH unless $rs; # unknown resource, just ignore
                            $rs->delete;
                        }
                        last SWITCH;
                    };
                    /^(man_)?allowed_ips$/ && do {
                        unless(exists $resource->{$k}) {
                            my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $k . '_grp');
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
                        my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $k);
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
            &$err_code(HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        };
    }

    my %nullable = (
        lock => 1,
    );

    foreach my $pref(keys %{ $resource }) {
        next if (not defined $resource->{$pref} and not $nullable{$pref});
        my $pref_rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $pref);
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
            &$err_code(HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        }

        try {
            my $vtype = ref $resource->{$pref};
            my $maxlen = 128;

            if($vtype eq "") {
                if(defined $resource->{$pref} and length($resource->{$pref}) > $maxlen) {
                    $c->log->error("preference '$pref' exceeds maximum length of $maxlen characters");
                    &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Preference '$pref' exceeds maximum length of $maxlen characters");
                    return;
                }
            } elsif($vtype eq "ARRAY") {
                foreach my $a(@{ $resource->{$pref} }) {
                    if(defined $a and length($a) > $maxlen) {
                        $c->log->error("element in preference '$pref' exceeds maximum length of $maxlen characters");
                        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Element in preference '$pref' exceeds maximum length of $maxlen characters");
                        return;
                    }
                }
            }

            if (($meta->data_type eq "boolean" or _exists_api_transform_in($c, $pref)) and JSON::is_bool($resource->{$pref})) {
                $vtype = "";
            }
            if($meta->max_occur == 1 && $vtype ne "" && $meta->data_type ne "blob") {
                $c->log->error("preference '$pref' has max_occur '".$meta->max_occur."', but value got passed in as '$vtype', expected flat value");
                &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid data type '$vtype' for preference '$pref', expected flat value");
                return;
            } elsif($meta->max_occur != 1 && $vtype ne "ARRAY") {
                $c->log->error("preference '$pref' has max_occur '".$meta->max_occur."', but value got passed in as '$vtype', expected ARRAY");
                &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid data type '$vtype' for preference '$pref', expected ARRAY");
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
                        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Unknown rewrite_rule_set '".$resource->{$pref}."'");
                        return;
                    }
                    foreach my $k(qw/
                                    caller_in_dpid callee_in_dpid
                                    caller_out_dpid callee_out_dpid
                                    caller_lnp_dpid callee_lnp_dpid/) {
                        my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, 'rewrite_'.$k);
                        if($rs->first) {
                            $rs->first->update({ value => $rwr_set->$k });
                        } else {
                            $rs->create({ value => $rwr_set->$k });
                        }
                    }
                    last SWITCH;
                };
                /^cdr_export_sclidui_rwrs$/ && do {
                    my $pref_name = $pref . "_id";
                    my $rwr_set = $c->model('DB')->resultset('voip_rewrite_rule_sets')->find({
                        name => $resource->{$pref},
                        reseller_id => $reseller_id,
                    });
                    unless($rwr_set) {
                        $c->log->error("no rewrite rule set '".$resource->{$pref}."' for reseller id $reseller_id found");
                        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Unknown rewrite_rule_set '".$resource->{$pref}."'");
                        return;
                    }
                    my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $pref_name);
                    if($rs->first) {
                        $rs->first->update({ value => $rwr_set->id });
                    } else {
                        $rs->create({ value => $rwr_set->id });
                    }
                    last SWITCH;
                };
                /^header_rule_set$/ && do {
                    my $hdr_set = $c->model('DB')->resultset('voip_header_rule_sets')->find({
                        name => $resource->{$pref},
                        reseller_id => $reseller_id,
                    });
                    unless ($hdr_set) {
                        $c->log->error("no header rule set '".$resource->{$pref}."' for reseller id $reseller_id found");
                        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Unknown header_rule_set '".$resource->{$pref}."'");
                        return;
                    }
                    my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $pref);
                    if ($rs->first) {
                        $rs->first->update({ value => $hdr_set->id });
                    } else {
                        $rs->create({ value => $hdr_set->id });
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
                        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Unknown ncos_level '".$resource->{$pref}."'");
                        return;
                    }
                    my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $pref_name);
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
                        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Unknown emergency mapping container '".$resource->{$pref}."'");
                        return;
                    }
                    my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $pref_name);
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
                        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Unknown $pref '".$resource->{$pref}."'");
                        return;
                    }
                    my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $pref);
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
                    my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $pref_name);
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
                        unless(_validate_ipnet($pref, $ip, $err_code)) {
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
                /^lock$/ && do {
                    my $v = $resource->{$pref};
                    return unless _check_pref_value($c, $meta, $v, $pref_type, $err_code);
                    NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                        c => $c,
                        prov_subscriber => $elem,
                        level => $v, # || 0
                    );
                    last SWITCH;
                };
                /^allowed_clis$/ && do {
                    if ($replace) {
                        #check duplicates in case of PUT
                        if ($resource->{$pref}) {
                            my %seen;
                            foreach my $allowed_cli (@{$resource->{$pref}}) {
                                next unless $seen{$allowed_cli}++;
                                $c->log->error("Duplicate $pref value: ".$allowed_cli);
                                &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Duplicate $pref value: ".$allowed_cli);
                                return;
                            }
                        }
                    }
                    else {
                        #in case of PATCH, check duplicates only for new values, since there could already be duplicates in some systems
                        if ($resource->{$pref} && $old_resource->{$pref}) {
                            my @new_clis = @{$resource->{$pref}}[scalar @{$old_resource->{$pref}} .. scalar @{$resource->{$pref}} - 1];
                            my %existing_clis = map {$_ => 1} @{$old_resource->{$pref}};
                            my ($allowed_cli) = grep { exists $existing_clis{$_} } @new_clis;
                            if ( $allowed_cli ) {
                                $c->log->error("Duplicate $pref value: ".$allowed_cli);
                                &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Duplicate $pref value: ".$allowed_cli);
                                return;
                            }
                        }
                    }
                };
                if ($meta->data_type eq 'blob') {
                    if ($resource->{$pref}->{data} ne '#blob'){
                        my $file = decode_base64($resource->{$pref}->{data});
                        my $rs = get_preference_rs($c, $TYPE_PREF_MAP->{$type}, $elem, $pref);
                        my $blob_rs = $c->model('DB')->resultset("voip_$TYPE_PREF_MAP->{$type}_preferences_blob");
                        if ($rs->first) {
                            my $blob = $blob_rs->search({ preference_id => $rs->first->id });
                            if ($blob->first) {
                                $blob->update({
                                    preference_id => $rs->first->id,
                                    $file ? (value => $file) : (),
                                    $resource->{$pref}->{content_type} ? (content_type => $resource->{$pref}->{content_type}) : (),
                                });
                            } else {
                                $blob_rs->create({
                                    preference_id => $rs->first->id,
                                    value => ($file ? $file : undef),
                                    content_type => $resource->{$pref}->{content_type},
                                });
                            }
                        } else {
                            $rs->create({ value => 0 });
                            $blob_rs->create({
                                preference_id => $rs->first->id,
                                value => ($file ? $file : undef),
                                content_type => $resource->{$pref}->{content_type},
                            });
                        }
                    }
                } elsif($meta->max_occur != 1) { #default
                    $pref_rs->delete;
                    foreach my $v(@{ $resource->{$pref} }) {
                        return unless _check_pref_value($c, $meta, $v, $pref_type, $err_code);
                        eval {
                            $v = _api_transform_in($c, $meta, $v);
                        };
                        if ($@) {
                            $c->log->error("Failed to transform pref value - $@");
                            &$err_code(HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error."); # TODO?
                            return;
                        }
						if(JSON::is_bool($v)){
							$v =  $v ? 1 : 0 ;
						}
                        $pref_rs->create({ value => $v });
                    }
                } elsif($pref_rs->first) {
                    return unless _check_pref_value($c, $meta, $resource->{$pref}, $pref_type, $err_code);
                    eval {
                        $resource->{$pref} = _api_transform_in($c, $meta, $resource->{$pref});
                    };
                    if ($@) {
                        $c->log->error("Failed to transform pref value - $@");
                        &$err_code(HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error."); # TODO?
                        return;
                    }
                    if(JSON::is_bool($resource->{$pref})){
						$resource->{$pref} =  $resource->{$pref} ? 1 : 0 ;
					}
                    $pref_rs->first->update({ value => $resource->{$pref} });
                } else {
                    return unless _check_pref_value($c, $meta, $resource->{$pref}, $pref_type, $err_code);
                    eval {
                        $resource->{$pref} = _api_transform_in($c, $meta, $resource->{$pref});
                    };
                    if ($@) {
                        $c->log->error("Failed to transform pref value - $@");
                        &$err_code(HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error."); # TODO?
                        return;
                    }
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
            &$err_code(HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        }
    }

    if($type eq "subscribers") {
        if(keys %{ $old_auth_prefs }) {
            my $new_auth_prefs = {};
            my $prov_subscriber = $elem;
            get_peer_auth_params(
                $c, $prov_subscriber, $new_auth_prefs);
            unless(compare($old_auth_prefs, $new_auth_prefs)) {
                $c->log->debug("peer_auth_params changed. Updating sems.");
                my $type = 'subscriber';
                try {
                    update_sems_peer_auth(
                        $c, $prov_subscriber, $type, $old_auth_prefs, $new_auth_prefs);
                } catch($e) {
                    $c->log->error("Failed to set peer registration: $e");
                    &$err_code(HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error."); # TODO?
                    return;
                }
            }
        }
    }

    return $item;
}

sub _init_transform {
    my ($transform,$conf) = @_;
    unless (defined $transform) {
        $transform = {};
        if (defined $conf) {
            foreach my $p (keys %$conf) {
                $transform->{$p} = {};
                foreach my $v (keys %{$conf->{$p}}) {
                    if ($v =~ /^([a-z0-9_]+)$CODE_SUFFIX_FNAME$/) {
                        ## no critic (BuiltinFunctions::ProhibitStringyEval)
                        $transform->{$p}->{$1} = eval($conf->{$p}->{$v});
                        die("$p '$v': " . $@) if $@;
                    } else {
                        $transform->{$p}->{$v} = $conf->{$p}->{$v};                    
                    }
                }
            }
        }
    }
    return $transform;
}

sub _exists_api_transform_in {
    my ($c, $pref) = @_;
    if ($c->request and $c->request->path =~/^api\//i) {
        $API_TRANSFORM_IN = _init_transform($API_TRANSFORM_IN,$c->config->{preference_in_transformations});
        if (exists $API_TRANSFORM_IN->{$pref}) {
            return 1;
        }
    }
    return 0;
}

sub _api_transform_in {
    my ($c, $meta, $value) = @_;
    if ($c->request and $c->request->path =~/^api\//i) {
        $API_TRANSFORM_IN = _init_transform($API_TRANSFORM_IN,$c->config->{preference_in_transformations});
        if (exists $API_TRANSFORM_IN->{$meta->attribute}) {
            if (defined $value) {
                my $v = $value;
                if (JSON::is_bool($v)) {
                    $v =  $v ? 1 : 0 ;
                }
                if (exists $API_TRANSFORM_IN->{$meta->attribute}->{$v}) {
                    $value = $API_TRANSFORM_IN->{$meta->attribute}->{$v};
                    if ('CODE' eq ref $value) {
                        eval {
                            $value = $value->($meta,$value);
                        };
                        if ($@) {
                            die($meta->attribute . ": " . $@);
                        }
                    }
                }
            }
        }
    }
    return $value;
}

sub _api_transform_out {
    my ($c, $meta, $value) = @_;
    if ($c->request and $c->request->path =~/^api\//i) {
        $API_TRANSFORM_OUT = _init_transform($API_TRANSFORM_OUT,$c->config->{preference_out_transformations});
        if (exists $API_TRANSFORM_OUT->{$meta->attribute}) {
            if (defined $value) {
                my $v = $value;
                if (JSON::is_bool($v)) {
                    $v =  $v ? 1 : 0 ;
                }
                if (exists $API_TRANSFORM_OUT->{$meta->attribute}->{$v}) {
                    $value = $API_TRANSFORM_OUT->{$meta->attribute}->{$v};
                    if ('CODE' eq ref $value) {
                        eval {
                            $value = $value->($meta,$value);
                        };
                        if ($@) {
                            die($meta->attribute . ": " . $@);
                        }
                    }
                }
            }
        }
    }
    return $value;
}

sub _check_pref_value {
    my ($c, $meta, $value, $pref_type, $err_code) = @_;

    return 1 if _exists_api_transform_in($c,$meta->attribute);
    
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { };
    }

    my $err;

    my $vtype = ref $value;
    if (($meta->data_type eq "boolean" and JSON::is_bool($value)) or $meta->data_type eq "blob") {
        $vtype = "";
    }
    unless($vtype eq "") {
        $c->log->error("preference '".$meta->attribute."' has invalid value data structure, expected plain value");
        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid data structure as value for element in preference '".$meta->attribute."', expected plain value");
        return;
    }

    SWITCH: for ($meta->data_type) {
        /^int$/ && do {
            $err = 1 unless is_int($value);
            last SWITCH;
        };
        /^boolean$/ && do {
            unless (JSON::is_bool($value)
                    or (is_int($value) and ($value == 0 or $value == 1))) {
                $err = 1;
            }
            last SWITCH;
        };
        # default
    } # SWITCH
    if($err) {
        $c->log->error("preference '".$meta->attribute."' has invalid value data type, expected '".$meta->data_type."'");
        &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid data type for element in preference '".$meta->attribute."', expected '".$meta->data_type."'");
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
            &$err_code(HTTP_UNPROCESSABLE_ENTITY, "Invalid enum value in preference '".$meta->attribute."'");
            return;
        }
    }

    return 1;
}

sub load_preference_list {
    my %params = @_;

    my $c = $params{c};
    my $pref_values = $params{pref_values};
    my $peer_pref = $params{peer_pref};
    my $reseller_pref = $params{reseller_pref};
    my $dom_pref = $params{dom_pref};
    my $dev_pref = $params{dev_pref};
    my $devprof_pref = $params{devprof_pref};
    my $fielddev_pref = $params{fielddev_pref};
    my $prof_pref = $params{prof_pref};
    my $usr_pref = $params{usr_pref};
    my $contract_pref = $params{contract_pref};
    my $contract_location_pref = $params{contract_location_pref};
    my $profile = $params{sub_profile};

    my $customer_view = $params{customer_view} // 0;
    my $cloudpbx_enabled = $c->config->{features}{cloudpbx};

    my $search_conditions = $params{search_conditions};

    my $pref_rs = $c->model('DB')
        ->resultset('voip_preference_groups')
        ->search({ 'voip_preferences.internal' => { '<=' => 0 },
            $contract_pref ? ('voip_preferences.contract_pref' => 1,
                -or => ['voip_preferences_enums.contract_pref' => 1,
                    'voip_preferences_enums.contract_pref' => undef]) : (),
            $contract_location_pref ? ('voip_preferences.contract_location_pref' => 1,
                -or => ['voip_preferences_enums.contract_location_pref' => 1,
                    'voip_preferences_enums.contract_location_pref' => undef]) : (),
            $peer_pref ? ('voip_preferences.peer_pref' => 1,
                -or => ['voip_preferences_enums.peer_pref' => 1,
                    'voip_preferences_enums.peer_pref' => undef]) : (),
            $reseller_pref ? ('voip_preferences.reseller_pref' => 1,
                -or => ['voip_preferences_enums.reseller_pref' => 1,
                    'voip_preferences_enums.reseller_pref' => undef]) : (),
            $dom_pref ? ('voip_preferences.dom_pref' => 1,
                -or => ['voip_preferences_enums.dom_pref' => 1,
                    'voip_preferences_enums.dom_pref' => undef]) : (),
            $dev_pref ? ('voip_preferences.dev_pref' => 1,
                -or => ['voip_preferences_enums.dev_pref' => 1,
                    'voip_preferences_enums.dev_pref' => undef]) : (),
            $devprof_pref ? ('voip_preferences.devprof_pref' => 1,
                -or => ['voip_preferences_enums.devprof_pref' => 1,
                    'voip_preferences_enums.devprof_pref' => undef]) : (),
            $fielddev_pref ? ('voip_preferences.fielddev_pref' => 1,
                -or => ['voip_preferences_enums.fielddev_pref' => 1,
                    'voip_preferences_enums.fielddev_pref' => undef]) : (),
            $prof_pref ? ('voip_preferences.prof_pref' => 1,
                -or => ['voip_preferences_enums.prof_pref' => 1,
                    'voip_preferences_enums.prof_pref' => undef]) : (),
            $usr_pref ? ('voip_preferences.usr_pref' => 1,
                -or => ['voip_preferences_enums.usr_pref' => 1,
                    'voip_preferences_enums.usr_pref' => undef]) : (),
            $customer_view ? ('voip_preferences.expose_to_customer' => 1) : (),
            $cloudpbx_enabled ? () : ('me.name' => { '!=' => 'Cloud PBX'}),
            }, {
                prefetch => {'voip_preferences' => 'voip_preferences_enums'},
            });
    if($prof_pref) {
        my @prof_attributes = $profile->profile_attributes->get_column('attribute_id')->all;
        $pref_rs = $pref_rs->search({
            'voip_preferences.id' => { in => \@prof_attributes }
        });
    }
    if($search_conditions) {
        if('ARRAY' eq ref $search_conditions){
            $pref_rs = $pref_rs->search(@$search_conditions);
        }else{
            $pref_rs = $pref_rs->search($search_conditions);
        }
    }
    my @pref_groups = $pref_rs->all;

    foreach my $group(@pref_groups) {
        my @group_prefs = $group->voip_preferences->all;

        foreach my $pref(@group_prefs) {

            my @values = @{
                exists $pref_values->{$pref->attribute}
                    ? $pref_values->{$pref->attribute}
                    : []
            };
            if($pref->attribute eq "rewrite_rule_set") {
                my $tmp;
                $pref->{rwrs_id} = $pref_values->{rewrite_caller_in_dpid} &&
                    ($tmp = $c->stash->{rwr_sets_rs}->search({
                        caller_in_dpid => $pref_values->{rewrite_caller_in_dpid}
                    })->first) ?
                    $tmp->id
                    : undef;
            } elsif($pref->attribute eq "cdr_export_sclidui_rwrs") {
                my $tmp;
                $pref->{rwrs_id} = $pref_values->{$pref->attribute . '_id'} &&
                    ($tmp = $c->stash->{rwr_sets_rs}->search({
                        id => $pref_values->{$pref->attribute . '_id'}
                    })->first) ?
                    $tmp->id
                    : undef;
            } elsif($pref->attribute eq "ncos") {
                if ($pref_values->{ncos_id} &&
                    (my $tmp = $c->stash->{ncos_levels_rs}
                        ->find($pref_values->{ncos_id}) )) {
                    $pref->{ncos_id} = $tmp->id;
                }
            } elsif($pref->attribute eq "adm_ncos") {
                if ($pref_values->{adm_ncos_id} &&
                    (my $tmp = $c->stash->{ncos_levels_rs}
                        ->find($pref_values->{adm_ncos_id}) )) {
                    $pref->{adm_ncos_id} = $tmp->id;
                }
            } elsif($pref->attribute eq "adm_cf_ncos") {
                if ($pref_values->{adm_cf_ncos_id} &&
                    (my $tmp = $c->stash->{ncos_levels_rs}
                        ->find($pref_values->{adm_cf_ncos_id}) )) {
                    $pref->{adm_cf_ncos_id} = $tmp->id;
                }
            } elsif($pref->attribute eq "emergency_mapping_container") {
                if ($pref_values->{emergency_mapping_container_id} &&
                    (my $tmp = $c->stash->{emergency_mapping_containers_rs}
                        ->find($pref_values->{emergency_mapping_container_id}) )) {
                    $pref->{emergency_mapping_container_id} = $tmp->id;
                }
            } elsif($pref->attribute eq "allowed_ips") {
                $pref->{allowed_ips_group_id} = $pref_values->{allowed_ips_grp};
                $pref->{allowed_ips_rs} = $c->model('DB')->resultset('voip_allowed_ip_groups')
                    ->search_rs({ group_id => $pref_values->{allowed_ips_grp} });
            } elsif($pref->attribute eq "man_allowed_ips") {
                $pref->{man_allowed_ips_group_id} = $pref_values->{man_allowed_ips_grp};
                $pref->{man_allowed_ips_rs} = $c->model('DB')->resultset('voip_allowed_ip_groups')
                    ->search_rs({ group_id => $pref_values->{man_allowed_ips_grp} });
            } elsif($c->stash->{subscriber} &&
                  ($pref->attribute eq "block_in_list" || $pref->attribute eq "block_out_list")) {
                foreach my $v(@values) {
                    my $prefix = "";
                    if($v =~ /^\#/) {
                        $v =~ s/^\#//;
                        $prefix = "#";
                    }

                    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
                        $v = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                            c => $c, subscriber => $c->stash->{subscriber}, number => $v, direction => 'caller_out'
                        );
                    }
                    $v = $prefix . $v;
                }
            }

            if($pref->data_type eq "enum") {
                $pref->{enums} = [];
                my @enums = $pref->voip_preferences_enums->all;
                push @{ $pref->{enums} }, @enums;
            }

            if($pref->max_occur != 1) {
                $pref->{value} = \@values;
            } else {
                $pref->{value} = $values[0];
            }
        }
        $group->{prefs} = \@group_prefs;
    }
    $c->stash(pref_groups => \@pref_groups);
}

sub create_preference_form {
    my %params = @_;

    my $c = $params{c};
    my $pref_rs = $params{pref_rs};
    my $base_uri = $params{base_uri};
    my $edit_uri = $params{edit_uri};
    my $enums    = $params{enums};
    my $blob_rs = $params{blob_rs};

    my $aip_grp_rs;
    my $aip_group_id;
    my $man_aip_grp_rs;
    my $man_aip_group_id;

    my $delete_param = $c->request->params->{delete};
    my $deactivate_param = $c->request->params->{deactivate};
    my $activate_param = $c->request->params->{activate};
    my $param_id = $delete_param || $deactivate_param || $activate_param;
    # only one parameter is processed at a time (?)
    if($param_id) {
        my $rs = $pref_rs->find($param_id);
        if($rs) {
            if($rs->attribute_id != $c->stash->{preference_meta}->id) {
                # Invalid param (dom_pref does not belong to current pref)
            } elsif($delete_param) {
                $rs->delete();
            } elsif ($deactivate_param) {
                $rs->update({value => "#".$rs->value});
            } elsif ($activate_param) {
                my $new_value = $rs->value;
                $new_value =~ s/^#//;
                $rs->update({value => $new_value});
            }
        }
    }

    my $preselected_value = undef;
    if ($c->stash->{preference_meta}->attribute eq "rewrite_rule_set") {
        my $rewrite_caller_in_dpid = $pref_rs->search({
                'attribute.attribute' => 'rewrite_caller_in_dpid'
            },{
                join => 'attribute'
            })->first;
        if (defined $rewrite_caller_in_dpid && (
            my $tmp = $preselected_value = $c->stash->{rwr_sets_rs}->search({
                    caller_in_dpid => $rewrite_caller_in_dpid->value,
                })->first
        )) {
            $preselected_value = $tmp->id;
        }
    } elsif ($c->stash->{preference_meta}->attribute eq "cdr_export_sclidui_rwrs") {

        my $rwrs_id_pref = $pref_rs->search({
                'attribute.attribute' => $c->stash->{preference_meta}->attribute . '_id'
            },{
                join => 'attribute'
            })->first;
        if (defined $rwrs_id_pref && (
            my $tmp = $preselected_value = $c->stash->{rwr_sets_rs}->search({
                    id => $rwrs_id_pref->value,
                })->first
        )) {
            $preselected_value = $tmp->id;
        }
    } elsif ($c->stash->{preference_meta}->attribute eq "ncos") {
        my $ncos_id_preference = $pref_rs->search({
                'attribute.attribute' => 'ncos_id'
            },{
                join => 'attribute'
            })->first;
        if (defined $ncos_id_preference) {
            $preselected_value = $ncos_id_preference->value;
        }
    } elsif ($c->stash->{preference_meta}->attribute eq "adm_ncos") {
        my $ncos_id_preference = $pref_rs->search({
                'attribute.attribute' => 'adm_ncos_id'
            },{
                join => 'attribute'
            })->first;
        if (defined $ncos_id_preference) {
            $preselected_value = $ncos_id_preference->value;
        }
    } elsif ($c->stash->{preference_meta}->attribute eq "adm_cf_ncos") {
        my $ncos_id_preference = $pref_rs->search({
                'attribute.attribute' => 'adm_cf_ncos_id'
            },{
                join => 'attribute'
            })->first;
        if (defined $ncos_id_preference) {
            $preselected_value = $ncos_id_preference->value;
        }
    } elsif ($c->stash->{preference_meta}->attribute eq "emergency_mapping_container") {
        my $container_id_preference = $pref_rs->search({
                'attribute.attribute' => 'emergency_mapping_container_id'
            },{
                join => 'attribute'
            })->first;
        if (defined $container_id_preference) {
            $preselected_value = $container_id_preference->value;
        }
    } elsif ($c->stash->{preference_meta}->attribute eq "allowed_ips") {
        my $allowed_ips_grp = $pref_rs->search({
                'attribute.attribute' => 'allowed_ips_grp'
            },{
                join => 'attribute'
            })->first;
        if (defined $allowed_ips_grp) {
            $aip_group_id = $allowed_ips_grp->value;
            $aip_grp_rs = $c->model('DB')->resultset('voip_allowed_ip_groups')
                ->search({ group_id => $aip_group_id });
        }
        my $delete_aig_param = $c->request->params->{delete_aig};
        if($delete_aig_param) {
            my $result = $aip_grp_rs->find($delete_aig_param);
            if($result) {
                $result->delete;
                unless ($aip_grp_rs->first) { #its empty
                    my $allowed_ips_grp_preference = $pref_rs->search({
                        'attribute.attribute' => 'allowed_ips_grp'
                    },{
                        join => 'attribute'
                    })->first;
                    $allowed_ips_grp_preference->delete
                        if (defined $allowed_ips_grp_preference);
                }
            }
        }
    } elsif ($c->stash->{preference_meta}->attribute eq "man_allowed_ips") {
        my $man_allowed_ips_grp = $pref_rs->search({
                'attribute.attribute' => 'man_allowed_ips_grp'
            },{
                join => 'attribute'
            })->first;
        if (defined $man_allowed_ips_grp) {
            $man_aip_group_id = $man_allowed_ips_grp->value;
            $man_aip_grp_rs = $c->model('DB')->resultset('voip_allowed_ip_groups')
                ->search({ group_id => $man_aip_group_id });
        }
        my $delete_man_aig_param = $c->request->params->{delete_man_aig};
        if($delete_man_aig_param) {
            my $result = $man_aip_grp_rs->find($delete_man_aig_param);
            if($result) {
                $result->delete;
                unless ($man_aip_grp_rs->first) { #its empty
                    my $man_allowed_ips_grp_preference = $pref_rs->search({
                        'attribute.attribute' => 'man_allowed_ips_grp'
                    },{
                        join => 'attribute'
                    })->first;
                    $man_allowed_ips_grp_preference->delete
                        if (defined $man_allowed_ips_grp_preference);
                }
            }
        }
    } elsif ($c->stash->{preference_meta}->max_occur == 1) {
        if ($c->stash->{preference}->first) {
            $preselected_value = $c->stash->{preference}->first->value unless ($c->stash->{preference_meta}->data_type eq 'blob');
        }
    }

    # this form is somewhat special, treat it without caching
    my $form = NGCP::Panel::Form::Preferences->new({
        ctx => $c,
        fields_data => [{
            meta => $c->stash->{preference_meta},
            enums => $enums,
            rwrs_rs => $c->stash->{rwr_sets_rs},
            hdrs_rs => $c->stash->{hdr_sets_rs},
            ncos_rs => $c->stash->{ncos_levels_rs},
            emergency_mapping_containers_rs => $c->stash->{emergency_mapping_containers_rs},
            sound_rs => $c->stash->{sound_sets_rs},
            contract_sound_rs => $c->stash->{contract_sound_sets_rs},
        }],
    });
    $form->create_structure([$c->stash->{preference_meta}->attribute]);
    # we have to translate this form separately since it bypasses caching in NGCP::Panel::Form
    if ( $c->stash->{preference_meta}->attribute !~ '(ncos|sound_set|emergency_mapping_container)$' ) {
        NGCP::Panel::Utils::I18N->translate_form($c, $form);
    }

    my $posted = ($c->request->method eq 'POST');
    if($posted && $c->stash->{preference_meta}->data_type eq 'blob') {
        # construct the form field name for blob data types,
        # since we need to pass the Catalyst::Upload object to req params
        my $field_name = $c->stash->{preference_meta}->attribute . '.file';
        $c->req->params->{$field_name} = $c->req->upload($field_name) if ($c->req->upload($field_name));
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => { $c->stash->{preference_meta}->attribute => $preselected_value },
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    # logging
    my %log_data = %{$c->request->params};
    # subscriber prefs
    if ($c->stash->{subscriber}) {
        %log_data = ( %log_data,
                      type          => 'subscriber',
                      subscriber_id => $c->stash->{subscriber}->id,
                      uuid          => $c->stash->{subscriber}->uuid,
                    );
    # domain prefs
    } elsif ($c->stash->{domain}) {
        %log_data = ( %log_data,
                      type      => 'domain',
                      domain_id => $c->stash->{domain}{id},
                      domain    => $c->stash->{domain}{domain},
                    );
    # customer prefs
    } elsif ($c->stash->{contract}) {
        %log_data = ( %log_data,
                      type        => 'customer',
                      customer_id => $c->stash->{contract}->id,
                      reseller_id => $c->stash->{contract}->contact->reseller_id,
                    );
    # peering prefs
    } elsif ($c->stash->{group} && $c->stash->{server}) {
        %log_data = ( %log_data,
                      type            => 'peer',
                      peer_group_id   => $c->stash->{group}{id},
                      peer_group_name => $c->stash->{group}{name},
                      peer_host_id    => $c->stash->{server}{id},
                      peer_host_name  => $c->stash->{server}{name},
                    );
    } elsif ($c->stash->{reseller}) {
        %log_data = ( %log_data,
                      type            => 'reseller',
                      reseller_id => $c->stash->{reseller}->id,
                    );
    } elsif ($c->stash->{devmod}) {
        %log_data = ( %log_data,
                      type            => 'dev',
                      device_id       => $c->stash->{devmod}->{id},
                      device_vendor   => $c->stash->{devmod}->{vendor},
                      device_model    => $c->stash->{devmod}->{model},
                      reseller_id     => $c->stash->{devmod}->{reseller_id},
                    );
    } elsif ($c->stash->{devprof}) {
        %log_data = ( %log_data,
                      type            => 'devprof',
                      device_id       => $c->stash->{devprof}->{id},
                      device_vendor   => $c->stash->{devprof}->{config_id},
                      device_model    => $c->stash->{devprof}->{name},
                    );
    } elsif ($c->stash->{pbx_device}) {
        %log_data = ( %log_data,
                      type            => 'fielddev',
                      device_id       => $c->stash->{pbx_device}->{id},
                      device_vendor   => $c->stash->{pbx_device}->{profile_id},
                      device_model    => $c->stash->{pbx_device}->{identifier},
                    );
    }

    if($posted && $form->validated) {
        my $preference_id = $c->stash->{preference}->first ? $c->stash->{preference}->first->id : undef;
        my $attribute = $c->stash->{preference_meta}->attribute;
        if ($attribute eq "allowed_ips") {
            unless(validate_ipnet($form->field($attribute))) {
                goto OUT;
            }

            unless (defined $aip_group_id) {
                try {
                    my $new_group = $c->model('DB')->resultset('voip_aig_sequence')
                        ->create({});
                    my $aig_preference_id = $c->model('DB')
                        ->resultset('voip_preferences')
                        ->find({ attribute => 'allowed_ips_grp' })
                        ->id;
                    $pref_rs->create({
                            value => $new_group->id,
                            attribute_id => $aig_preference_id,
                        });
                    $aip_group_id = $new_group->id;
                    $aip_grp_rs = $c->model('DB')->resultset('voip_allowed_ip_groups')
                        ->search({ group_id => $aip_group_id });
                    $c->model('DB')->resultset('voip_aig_sequence')->search_rs({
                            id => { '<' => $new_group->id },
                        })->delete_all;
                    NGCP::Panel::Utils::Message::info(
                        c => $c,
                        type => 'internal',
                        data => \%log_data,
                        desc => $c->loc('ip group sequence successfully generated'),
                    );
                } catch($e) {
                    NGCP::Panel::Utils::Message::error(
                        c => $c,
                        error => $e,
                        data => \%log_data,
                        desc  => $c->loc('Failed to generate ip group sequence'),
                    );
                    $c->response->redirect($base_uri);
                    return 1;
                }
            }
            try {
                $aip_grp_rs->create({
                    group_id => $aip_group_id,
                    ipnet => $form->field($attribute)->value,
                });
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    type => 'internal',
                    data => \%log_data,
                    desc => $c->loc('allowed_ip_grp successfully created'),
                );
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $e,
                    data  => \%log_data,
                    desc  => $c->loc('Failed to create allowed_ip_grp'),
                );
                $c->response->redirect($base_uri);
                return 1;
            }
        } elsif ($attribute eq "man_allowed_ips") {
            unless(validate_ipnet($form->field($attribute))) {
                goto OUT;
            }
            unless (defined $man_aip_group_id) {
                try {
                    my $new_group = $c->model('DB')->resultset('voip_aig_sequence')
                        ->create({});
                    my $man_aig_preference_id = $c->model('DB')
                        ->resultset('voip_preferences')
                        ->find({ attribute => 'man_allowed_ips_grp' })
                        ->id;
                    $pref_rs->create({
                            value => $new_group->id,
                            attribute_id => $man_aig_preference_id,
                        });
                    $man_aip_group_id = $new_group->id;
                    $man_aip_grp_rs = $c->model('DB')->resultset('voip_allowed_ip_groups')
                        ->search({ group_id => $man_aip_group_id });
                    $c->model('DB')->resultset('voip_aig_sequence')->search_rs({
                            id => { '<' => $new_group->id },
                        })->delete_all;
                    NGCP::Panel::Utils::Message::info(
                        c => $c,
                        type => 'internal',
                        data => \%log_data,
                        desc => $c->loc('Manual ip group sequence successfully generated'),
                    );
                } catch($e) {
                    NGCP::Panel::Utils::Message::error(
                        c => $c,
                        error => $e,
                        data  => \%log_data,
                        desc  => $c->loc('Failed to generate manual ip group sequence'),
                    );
                    $c->response->redirect($base_uri);
                    return 1;
                }
            }
            try {
                $man_aip_grp_rs->create({
                    group_id => $man_aip_group_id,
                    ipnet => $form->field($attribute)->value,
                });
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    type => 'internal',
                    data => \%log_data,
                    desc => $c->loc('man_allowed_ip_grp successfully created'),
                );
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $e,
                    data  => \%log_data,
                    desc  => $c->loc('Failed to create man_allowed_ip_grp'),
                );
                $c->response->redirect($base_uri);
                return 1;
            }
        } elsif ($attribute eq "allowed_clis") {
            my $v = $form->field($attribute)->value;
            my $existing_cli = $pref_rs->search({
                attribute_id => $c->stash->{preference_meta}->id,
                value => $v
            });
            if ($existing_cli->first) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $c->loc('Duplicate preference [_1]', $attribute),
                    data  => \%log_data,
                    desc  => $c->loc('Duplicate preference [_1]', $attribute),
                );
                $c->response->redirect($base_uri);
                return 1;
            }
            else {
                $pref_rs->create({
                    attribute_id => $c->stash->{preference_meta}->id,
                    value => $form->values->{$c->stash->{preference_meta}->attribute},
                });
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    data => \%log_data,
                    desc => $c->loc('Preference [_1] successfully created', $attribute),
                );
            }
        } elsif ($c->stash->{preference_meta}->max_occur != 1) {
            if($c->stash->{subscriber} &&
               ($c->stash->{preference_meta}->attribute eq "block_in_list" || $c->stash->{preference_meta}->attribute eq "block_out_list")) {
                my $v = $form->values->{$c->stash->{preference_meta}->attribute};

                if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
                    $v =~ s/^(.+?)([*\[].*$)/$1/; # strip any trailing shell pattern stuff
                    my $suffix = $2 // "";
                    $form->values->{$c->stash->{preference_meta}->attribute} = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                        c => $c, subscriber => $c->stash->{subscriber}, number => $v, direction => 'callee_in'
                    );

                    # rewrite it back for immediate display
                    $v = $form->values->{$c->stash->{preference_meta}->attribute};
                    $v = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                        c => $c, subscriber => $c->stash->{subscriber}, number => $v, direction => 'caller_out'
                    );

                    # restore stripped shell pattern stuff
                    $form->values->{$c->stash->{preference_meta}->attribute} .= $suffix;
                    $v .= $suffix;

                }
            }
            try {
                $pref_rs->create({
                    attribute_id => $c->stash->{preference_meta}->id,
                    value => $form->values->{$c->stash->{preference_meta}->attribute},
                });
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    data => \%log_data,
                    desc => $c->loc('Preference [_1] successfully created', $attribute),
                );
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $e,
                    data  => \%log_data,
                    desc  => $c->loc('Failed to create preference [_1]', $attribute),
                );
                $c->response->redirect($base_uri);
                return 1;
            }
        } elsif ($attribute eq "rewrite_rule_set") {
            my $selected_rwrs = $c->stash->{rwr_sets_rs}->find(
                $form->field($attribute)->value
            );
            set_rewrite_preferences(
                c             => $c,
                rwrs_result   => $selected_rwrs,
                pref_rs       => $pref_rs,
            );
            NGCP::Panel::Utils::Message::info(
                c => $c,
                data => \%log_data,
                desc => $c->loc('Preference [_1] successfully updated', $attribute),
            );
            $c->response->redirect($base_uri);
            return 1;
        } elsif ($attribute eq "cdr_export_sclidui_rwrs") {
            my $selected_rwrs = $c->stash->{rwr_sets_rs}->find(
                $form->field($attribute)->value
            );
            set_rewrite_id_preference(
                c             => $c,
                rwrs_result   => $selected_rwrs,
                pref_rs       => $pref_rs,
                rwrs_pref_attribute => $attribute,
            );
            NGCP::Panel::Utils::Message::info(
                c => $c,
                data => \%log_data,
                desc => $c->loc('Preference [_1] successfully updated', $attribute),
            );
            $c->response->redirect($base_uri);
            return 1;
        } elsif ($attribute eq "ncos" || $attribute eq "adm_ncos" || $attribute eq "adm_cf_ncos") {
            my $selected_level = $c->stash->{ncos_levels_rs}->find(
                $form->field($attribute)->value
            );
            my $attribute_id = $c->model('DB')->resultset('voip_preferences')
                ->find({attribute => $attribute."_id"})->id;

            try {
                my $preference = $pref_rs->search({ attribute_id => $attribute_id });
                if(!defined $selected_level) {
                    $preference->first->delete if $preference->first;
                } elsif($preference->first) {
                    $preference->first->update({ value => $selected_level->id });
                } else {
                    $preference->create({ value => $selected_level->id });
                }
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    data => \%log_data,
                    desc => $c->loc('Preference [_1] successfully updated', $attribute),
                );
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $e,
                    data  => \%log_data,
                    desc  => $c->loc('Failed to update preference [_1]', $attribute),
                );
                $c->response->redirect($base_uri);
                return 1;
            }
            $c->response->redirect($base_uri);
            return 1;
        } elsif ($attribute eq "emergency_mapping_container") {
            my $selected_container = $c->stash->{emergency_mapping_containers_rs}->find(
                $form->field($attribute)->value
            );
            my $attribute_id = $c->model('DB')->resultset('voip_preferences')
                ->find({attribute => $attribute."_id"})->id;

            try {
                my $preference = $pref_rs->search({ attribute_id => $attribute_id });
                if(!defined $selected_container) {
                    $preference->first->delete if $preference->first;
                } elsif($preference->first) {
                    $preference->first->update({ value => $selected_container->id });
                } else {
                    $preference->create({ value => $selected_container->id });
                }
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    data => \%log_data,
                    desc => $c->loc('Preference [_1] successfully updated', $attribute),
                );
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $e,
                    data  => \%log_data,
                    desc  => $c->loc('Failed to update preference [_1]', $attribute),
                );
                $c->response->redirect($base_uri);
                return 1;
            }
            $c->response->redirect($base_uri);
            return 1;
        } elsif ($attribute eq "sound_set") {
            my $selected_set = $c->stash->{sound_sets_rs}->find(
                $form->field($attribute)->value
            );

            try {
                my $preference = $pref_rs->search({
                    attribute_id => $c->stash->{preference_meta}->id });
                if(!defined $selected_set) {
                    $preference->first->delete if $preference->first;
                } elsif($preference->first) {
                    $preference->first->update({ value => $selected_set->id });
                } else {
                    $preference->create({ value => $selected_set->id });
                }
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    data => \%log_data,
                    desc => $c->loc('Preference [_1] successfully updated', $attribute),
                );
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $e,
                    data  => \%log_data,
                    desc  => $c->loc('Failed to update preference [_1]', $attribute),
                );
                $c->response->redirect($base_uri);
                return 1;
            }
            $c->response->redirect($base_uri);
            return 1;
        } elsif ($attribute eq "contract_sound_set") {
            my $selected_set = $c->stash->{contract_sound_sets_rs}->find(
                $form->field($attribute)->value
            );

            try {
                my $preference = $pref_rs->search({
                    attribute_id => $c->stash->{preference_meta}->id });
                if(!defined $selected_set) {
                    $preference->first->delete if $preference->first;
                } elsif($preference->first) {
                    $preference->first->update({ value => $selected_set->id });
                } else {
                    $preference->create({ value => $selected_set->id });
                }
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    data => \%log_data,
                    desc => $c->loc('Preference [_1] successfully updated', $attribute),
                );
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $e,
                    data  => \%log_data,
                    desc  => $c->loc('Failed to update preference [_1]', $attribute),
                );
                $c->response->redirect($base_uri);
                return 1;
            }
            $c->response->redirect($base_uri);
            return 1;
        } elsif ($attribute eq "lock") {
            my $v = $form->field($attribute)->value;
            #undef $v if (defined $v && $v eq '');
            try {
                NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                        c => $c,
                        prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
                        level => $v,
                    );
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    data  => \%log_data,
                    desc  => $c->loc('Preference [_1] successfully updated', $attribute),
                );
            } catch($e) {
                   NGCP::Panel::Utils::Message::error(
                        c => $c,
                        error => $e,
                        data  => \%log_data,
                        desc  => $c->loc('Failed to update preference [_1]', $attribute),
                    );
                    $c->response->redirect($base_uri);
                    return 1;
            }
            $c->response->redirect($base_uri);
            return 1;
        } else {
            if( ($c->stash->{preference_meta}->data_type ne 'enum' &&
                (!defined $form->field($attribute)->value || $form->field($attribute)->value eq '')) ||
                ($c->stash->{preference_meta}->data_type eq 'enum' &&
                ! defined $form->field($attribute)->value)
                ) {
                try {
                    my $preference = $pref_rs->find($preference_id);
                    $preference->delete if $preference;
                    NGCP::Panel::Utils::Message::info(
                        c => $c,
                        data => \%log_data,
                        desc => $c->loc('Preference [_1] successfully deleted', $attribute),
                    );
                } catch($e) {
                    NGCP::Panel::Utils::Message::error(
                        c => $c,
                        error => $e,
                        data  => \%log_data,
                        desc  => $c->loc('Failed to delete preference [_1]', $attribute),
                    );
                    $c->response->redirect($base_uri);
                    return 1;
                }
            } elsif($c->stash->{preference_meta}->data_type eq 'boolean' &&
                    $form->field($attribute)->value == 0) {
                try {
                    my $preference = $pref_rs->find($preference_id);
                    $preference->delete if $preference;
                    NGCP::Panel::Utils::Message::info(
                        c => $c,
                        data => \%log_data,
                        desc => $c->loc('Preference [_1] successfully deleted', $attribute),
                    );
                } catch($e) {
                    NGCP::Panel::Utils::Message::error(
                        c => $c,
                        error => $e,
                        data  => \%log_data,
                        desc  => $c->loc('Failed to delete preference [_1]', $attribute),
                    );
                    $c->response->redirect($base_uri);
                    return 1;
                }
            } elsif($c->stash->{preference_meta}->data_type eq 'blob') {
                try {
                    my $preference = $pref_rs->search({ attribute_id => $c->stash->{preference_meta}->id });
                    my $file = $form->field("$attribute.file")->value;
                    my $content_type = $form->field("$attribute.content_type")->value;
                    if ($c->req->body_parameters->{"$attribute.delete"}) {
                        $preference->delete if $preference;
                    } elsif ($c->req->body_parameters->{"$attribute.download"}) {
                        my $blob = $blob_rs->search({ preference_id => $preference->first->id });
                        my $data = $blob->first->value;
                        my $ft = File::Type->new();
                        $c->response->header('Content-Disposition' => 'attachment; filename="' . $blob->first->id . '-' . $attribute . '"');
                        $c->response->content_type($ft->mime_type($blob->first->value) || $blob->first->content_type);
                        $c->response->body($data);
                        return 1;
                    } elsif ($preference->first) {
                        my $blob = $blob_rs->search({ preference_id => $preference->first->id });
                        if ($blob->first) {
                            $blob->update({
                                preference_id => $preference->first->id,
                                $file ? (value => $file->slurp) : (),
                                $content_type ? (content_type => $content_type) : (),
                            });
                        } else {
                            $blob_rs->create({
                                preference_id => $preference->first->id,
                                value => ($file ? $file->slurp : undef),
                                content_type => $content_type,
                            });
                        }
                    } else {
                        $preference->create({ value => 0 });
                        $blob_rs->create({
                            preference_id => $preference->first->id,
                            value => ($file ? $file->slurp : undef),
                            content_type => $content_type,
                        });
                    }
                    NGCP::Panel::Utils::Message::info(
                        c => $c,
                        data  => \%log_data,
                        desc  => $c->loc('Preference [_1] successfully updated', $attribute),
                    );
                } catch($e) {
                   NGCP::Panel::Utils::Message::error(
                        c => $c,
                        error => $e,
                        data  => \%log_data,
                        desc  => $c->loc('Failed to update preference [_1]', $attribute),
                    );
                    $c->response->redirect($base_uri);
                    return 1;
                }
            } else {
                try {
                    $pref_rs->update_or_create({
                        id => $preference_id,
                        attribute_id => $c->stash->{preference_meta}->id,
                        value => $form->field($attribute)->value,
                    });
                    NGCP::Panel::Utils::Message::info(
                        c => $c,
                        data  => \%log_data,
                        desc  => $c->loc('Preference [_1] successfully updated', $attribute),
                    );
                } catch($e) {
                   NGCP::Panel::Utils::Message::error(
                        c => $c,
                        error => $e,
                        data  => \%log_data,
                        desc  => $c->loc('Failed to update preference [_1]', $attribute),
                    );
                    $c->response->redirect($base_uri);
                    return 1;
                }
            }
            $c->response->redirect($base_uri);
            return 1;
         }
    }

    OUT:

    my $preference_values = [];
    foreach my $p ( $c->stash->{preference}->all ) {
        my $v = $p->value;
        $v =~ s/^\#//;
        if( ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") &&
            $c->stash->{subscriber} &&
            (   $c->stash->{preference_meta}->attribute eq "block_in_list" ||
                $c->stash->{preference_meta}->attribute eq "block_out_list" )
            ) {
            $v = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                c => $c, subscriber => $c->stash->{subscriber}, number => $v, direction => 'caller_out',
            );
        }

        push @{ $preference_values }, {
                id => $p->id,
                value => $v,
                disabled => !!($p->value =~ m/^\#/),
            };
    }

    $form->process if ($posted && $form->validated);
    $c->stash(form              => $form,
              aip_grp_rs        => $aip_grp_rs,
              man_aip_grp_rs    => $man_aip_grp_rs,
              preference_values => $preference_values);

    return 1;
}

sub _check_profile {
    my ($c, $pref_name, $attr) = @_;
    my $shown = $c->model('DB')->resultset('voip_preferences')->find({
        'attribute' => $pref_name
    });
    return unless($shown && $attr->{$shown->id});
    return 1;
}

sub set_rewrite_preferences {
    my %params = @_;

    my $c             = $params{c};
    my $rwrs_result   = $params{rwrs_result};
    my $pref_rs       = $params{pref_rs};

    for my $dprules(qw/
                    callee_in_dpid caller_in_dpid
                    callee_out_dpid caller_out_dpid
                    callee_lnp_dpid caller_lnp_dpid/) {

        my $attribute_id = $c->model('DB')->resultset('voip_preferences')
            ->find({attribute => "rewrite_$dprules"})->id;
        my $preference = $pref_rs->search({
            attribute_id => $attribute_id,
        });

        if(!defined $rwrs_result) {
            $preference->first->delete if $preference->first;
        } elsif($preference->first) {
            $preference->first->update({ value => $rwrs_result->$dprules });
        } else {
            $preference->create({ value => $rwrs_result->$dprules });
        }
    }

}

sub set_rewrite_id_preference {
    my %params = @_;

    my $c = $params{c};
    my $rwrs_result = $params{rwrs_result};
    my $pref_rs = $params{pref_rs};
    my $rwrs_pref_attribute = $params{rwrs_pref_attribute};

    my $attribute_id = $c->model('DB')->resultset('voip_preferences')
        ->find({attribute => $rwrs_pref_attribute . '_id'})->id;
    my $preference = $pref_rs->search({
        attribute_id => $attribute_id,
    });

    if(!defined $rwrs_result) {
        $preference->first->delete if $preference->first;
    } elsif($preference->first) {
        $preference->first->update({ value => $rwrs_result->id });
    } else {
        $preference->create({ value => $rwrs_result->id });
    }

}

sub get_usr_preferences_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $prov_subscriber = $params{prov_subscriber};
    my $schema = $params{schema} // $c->model('DB');
    my $get_rows = $params{get_rows};

    my $pref_rs = $schema->resultset('voip_usr_preferences')->search({
            'attribute.usr_pref' => 1,
            $attribute ? ( 'attribute.attribute' => (('ARRAY' eq ref $attribute) ? { '-in' => $attribute } : $attribute ) ) : ()  ,
            $prov_subscriber ? ('me.subscriber_id' => $prov_subscriber->id) : (),
        },{
            '+select' => ['attribute.attribute'],
            '+as' => ['attribute'],
            'join' => 'attribute',
    });

    return $pref_rs;
}

sub get_preferences_rs {
    my %params = @_;

    my $c = $params{c};
    my $preferences_type = $params{type};
    my $attribute = $params{attribute};
    my $item_id = $params{id};
    my $schema = $params{schema} // $c->model('DB');

    my %config = (
        'usr'      => [qw/voip_usr_preferences usr_pref subscriber_id/],
        'dom'      => [qw/voip_dom_preferences dom_pref domain_id/],
        'prof'     => [qw/voip_prof_preferences prof_pref profile_id/],
        'peer'     => [qw/voip_peer_preferences peer_pref peer_host_id/],
        'reseller' => [qw/reseller_preferences reseller_pref reseller_id/],
        'dev'      => [qw/voip_dev_preferences dev_pref device_id/],
        'devprof'  => [qw/voip_devprof_preferences devprof_pref profile_id/],
        'fielddev' => [qw/voip_fielddev_preferences fielddev_pref device_id/],
        'contract' => [qw/voip_contract_preferences contract_pref contract_id/],
        'contract_location' => [qw/voip_contract_preferences contract_location_pref location_id/],
    );
    my $pref_rs = $schema->resultset($config{$preferences_type}->[0])->search({
            'attribute.'.$config{$preferences_type}->[1] => 1,  ## no critic (ProhibitCommaSeparatedStatements)
            $attribute ? ( 'attribute.attribute' => (('ARRAY' eq ref $attribute) ? { '-in' => $attribute } : $attribute ) ) : ()  ,
            $item_id ? ('me.'.$config{$preferences_type}->[2] => $item_id) : (),
        },{
            '+select' => ['attribute.attribute'],
            '+as' => ['attribute'],
            'join' => 'attribute',
    });

    return $pref_rs;
}

sub get_preference_rs {
    my ($c, $type, $elem, $attr, $params) = @_;

    my $location_id     = $params->{location_id} // undef;
    my $subscriberadmin = $params->{subscriberadmin} // ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") ? 1 : 0;

    my $rs;
    if($type eq "dom") {
        $rs = get_dom_preference_rs(
            c => $c,
            attribute => $attr,
            prov_domain => $elem,
        );
    } elsif($type eq "prof") {
        $rs = get_prof_preference_rs(
            c => $c,
            attribute => $attr,
            profile => $elem,
        );
    } elsif($type eq "usr") {
        $rs = get_usr_preference_rs(
            c => $c,
            attribute => $attr,
            prov_subscriber => $elem,
            $subscriberadmin ? (subscriberadmin => 1) : (),
        );
    } elsif($type eq "peer") {
        $rs = get_peer_preference_rs(
            c => $c,
            attribute => $attr,
            peer_host => $elem,
        );
    } elsif($type eq "reseller") {
        $rs = get_reseller_preference_rs(
            c => $c,
            attribute => $attr,
            reseller => $elem,
        );
    } elsif($type eq "dev") {
        $rs = get_dev_preference_rs(
            c => $c,
            attribute => $attr,
            device => $elem,
        );
    } elsif($type eq "devprof") {
        $rs = get_devprof_preference_rs(
            c => $c,
            attribute => $attr,
            profile => $elem,
        );
    } elsif($type eq "fielddev") {
        $rs = get_fielddev_preference_rs(
            c => $c,
            attribute => $attr,
            device => $elem,
        );
    } elsif($type eq "contract") {
        $rs = get_contract_preference_rs(
            c => $c,
            attribute => $attr,
            contract => $elem,
            location_id => $location_id,
        );
    }
    return $rs;
}

sub get_chained_preference_rs {
    my ($c, $attr, $elem, $params) = @_;

    my $type_order_default = {
        'usr' => [qw/usr prof dom/],
    };
    my $elem_sub_type_id = {
        usr => {
            prof => $elem->voip_subscriber_profile,
            dom => $elem->domain,
        }
    };
    my $preference = $c->model('DB')
        ->resultset('voip_preferences')
        ->find({ attribute => $attr });

    my $type_meta = $params->{type} // 'usr';
    my $type_order = $params->{order} // $type_order_default->{$type_meta};
    my $provisioning_subscriber = $params->{provisioning_subscriber};


    my $attribute_value_rs;
    my $preference_desc = { $preference->get_columns };
    foreach my $preference_type ( grep {$preference_desc->{$_.'_pref'} } @{$type_order} ) {
        my ($preference_elem_id, $preference_elem);
        if ($preference_type eq $type_meta){
            $preference_elem = $elem;
         } else {
            $preference_elem = $elem_sub_type_id->{$type_meta}->{$preference_type};
        }
        if ($preference_elem) {
            $preference_elem_id = $preference_elem->id;
        }
        if ($preference_elem_id) {
            #$attribute_value_rs = get_preferences_rs(
            #    c => $c,
            #    type => $preference_type,
            #    attribute => $attr,
            #    id => $preference_elem_id,
            #);
            $attribute_value_rs = get_preference_rs(
                $c,
                $preference_type,
                $preference_elem,
                $attr,
                { exists $params->{subscriberadmin} ? (subscriberadmin => $params->{subscriberadmin} ) : () },
            );
            if ($attribute_value_rs->first) {
                return $attribute_value_rs;
            }
        }
    }
    return $attribute_value_rs;
}

sub get_usr_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $prov_subscriber = $params{prov_subscriber};
    my $schema = $params{schema} // $c->model('DB');
    my $is_subadmin = $params{subscriberadmin};

    my $pref_rs = $schema->resultset('voip_preferences')->search_rs({
            attribute => $attribute,
            usr_pref => 1,
            $is_subadmin ? (expose_to_customer => 1) : (),
        })->first;
    return unless($pref_rs);

    my $attribute_id = $pref_rs->id;

    # filter by allowed attrs from profile
    if ($is_subadmin && $prov_subscriber && $prov_subscriber->voip_subscriber_profile) {
        my $found_attr = $prov_subscriber->voip_subscriber_profile
            ->profile_attributes->search_rs({
                attribute_id => $attribute_id,
                })->first;
        unless ($found_attr) {
            $c->log->debug("get_usr_preference_rs skipping attr '$attribute' not in profile");
            return;
        }
    }

    $pref_rs = $pref_rs->voip_usr_preferences;
    if($prov_subscriber) {
        $pref_rs = $pref_rs->search({
                subscriber_id => $prov_subscriber->id,
                attribute_id  => $attribute_id
            });
    }

    return $pref_rs;
}

sub get_prof_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $profile = $params{profile};
    my $schema = $params{schema} // $c->model('DB');

    my $pref_rs = $schema->resultset('voip_preferences')->find({
            attribute => $attribute, 'prof_pref' => 1,
        });
    return unless($pref_rs);
    $pref_rs = $pref_rs->voip_prof_preferences;
    if($profile) {
        # TODO: if profile is not set, it should return an rs with no entries?
        $pref_rs = $pref_rs->search({
                profile_id => $profile->id,
            });
    }
    return $pref_rs;
}

sub get_dom_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $prov_domain = $params{prov_domain};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'dom_pref' => 1,
        });
    return unless($preference);
    return $preference->voip_dom_preferences->search_rs({
            domain_id => $prov_domain->id,
        });
}

sub get_peer_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $host = $params{peer_host};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'peer_pref' => 1,
        });
    return unless($preference);
    return $preference->voip_peer_preferences->search_rs({
            peer_host_id => $host->id,
        });
}

sub get_reseller_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $reseller = $params{reseller};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'reseller_pref' => 1,
        });
    return unless($preference);
    return $preference->reseller_preferences->search_rs({
            reseller_id => $reseller->id,
        });
}

sub get_dev_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $device = $params{device};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'dev_pref' => 1,
        });
    return unless($preference);
    return $preference->voip_dev_preferences->search_rs({
           device_id => $device->id,
        });
}

sub get_devprof_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $profile = $params{profile};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'devprof_pref' => 1,
        });
    return unless($preference);
    return $preference->voip_devprof_preferences->search_rs({
           profile_id => $profile->id,
        });
}

sub get_fielddev_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $device = $params{device};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'fielddev_pref' => 1,
        });
    return unless($preference);
    return $preference->voip_fielddev_preferences->search_rs({
           device_id => $device->id,
        });
}

sub get_contract_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $contract = $params{contract};
    my $location_id = $params{location_id} || undef;

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute,
            contract_pref => 1,
            contract_location_pref => $location_id ? 1 : 0,
        });
    return unless($preference);
    return $preference->voip_contract_preferences->search_rs({
            contract_id => $contract->id,
            location_id => $location_id,
        });
}

sub update_sems_peer_auth {
    my ($c, $prov_object, $type, $old_auth_prefs, $new_auth_prefs) = @_;
    # prov_object can be either peering or subscriber

    if(!_is_peer_auth_active($c, $old_auth_prefs) &&
        _is_peer_auth_active($c, $new_auth_prefs)) {

        NGCP::Panel::Utils::Sems::create_peer_registration(
            $c, $prov_object, $type, $new_auth_prefs);
    } elsif( _is_peer_auth_active($c, $old_auth_prefs) &&
            !_is_peer_auth_active($c, $new_auth_prefs)) {

        NGCP::Panel::Utils::Sems::delete_peer_registration(
            $c, $prov_object, $type, $old_auth_prefs);
    } elsif(_is_peer_auth_active($c, $old_auth_prefs) &&
            _is_peer_auth_active($c, $new_auth_prefs)){

        NGCP::Panel::Utils::Sems::update_peer_registration(
            $c, $prov_object, $type, $new_auth_prefs, $old_auth_prefs);
    }

    return;
}

sub get_peer_auth_params {
    my ($c, $prov_subscriber, $prefs) = @_;

    foreach my $attribute (qw/peer_auth_user peer_auth_hf_user peer_auth_realm peer_auth_pass peer_auth_register/){
        my $rs;
        $rs = get_usr_preference_rs(
            c => $c,
            attribute => $attribute,
            prov_subscriber => $prov_subscriber
        );
        $prefs->{$attribute} = $rs->first ? $rs->first->value : undef;
    }
}

sub _is_peer_auth_active {
    my ($c, $prefs) = @_;
    if(defined $prefs->{peer_auth_register} && $prefs->{peer_auth_register} == 1 &&
       defined $prefs->{peer_auth_user} &&
       defined $prefs->{peer_auth_realm} &&
       defined $prefs->{peer_auth_pass}) {

        return 1;
    }
    return;
}

sub set_provisoning_voip_subscriber_first_int_attr_value {
    my %params = @_;

    my $c = $params{c};
    my $prov_subscriber= $params{prov_subscriber};
    my $new_value = $params{value};
    if (defined $new_value) {
        $new_value =~ s/^\s+|\s+$//g;
        undef $new_value if $new_value eq '';
    }
    my $attribute = $params{attribute};

    return unless $prov_subscriber;

    my $rs = get_usr_preference_rs(
        c => $c,
        prov_subscriber => $prov_subscriber,
        attribute => $attribute,
    );
    try {
        if($rs->first) {
            if(($new_value // 0) == 0) {
                $rs->first->delete;
            } else {
                $rs->first->update({ value => $new_value });
            }
        } elsif(($new_value // 0) > 0) {
            $rs->create({ value => $new_value });
        } # nothing to do for level 0, if no lock is set yet
    } catch($e) {
        $c->log->error("failed to set provisioning_voip_subscriber attribute '$attribute': $e");
        $e->rethrow;
    }
}

sub get_provisoning_voip_subscriber_first_int_attr_value {
    my %params = @_;

    my $c = $params{c};
    my $prov_subscriber= $params{prov_subscriber};
    my $attribute = $params{attribute};

    return unless $prov_subscriber;

    my $rs = get_usr_preference_rs(
        c => $c,
        prov_subscriber => $prov_subscriber,
        attribute => $attribute,
    );
    try {
        return ($rs->first ? $rs->first->value : undef);
    } catch($e) {
        $c->log->error("failed to get provisioning_voip_subscriber attribute '$attribute': $e");
        $e->rethrow;
    }
}

sub api_preferences_defs {
    my %params = @_;

    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my $preferences_group = $params{preferences_group};

    my $is_subadmin = ($c->user->roles eq 'subscriberadmin' || $c->user->roles eq 'subscriber');

    my $preferences = $c->model('DB')->resultset('voip_preferences')->search({
        internal => { '!=' => 1 }, # also fetch -1 for ncos, rwr
        $preferences_group => 1,
        $is_subadmin ? (expose_to_customer => 1) : (),
    });

    my $resource = {};
    for my $pref($preferences->all) {
        my $fields = { $pref->get_inflated_columns };
        # remove internal fields
        delete @{$fields}{qw/type attribute expose_to_customer internal peer_pref reseller_pref usr_pref dom_pref contract_pref contract_location_pref prof_pref voip_preference_groups_id id modify_timestamp/};
        $fields->{max_occur} = int($fields->{max_occur});
        $fields->{read_only} = JSON::Types::bool($fields->{read_only});
        if($fields->{data_type} eq "enum") {
            my @enums = $pref->voip_preferences_enums->search({
                $preferences_group => 1,
            })->all;
            $fields->{enum_values} = [];
            foreach my $enum(@enums) {
                my $efields = { $enum->get_inflated_columns };
                delete @{$efields}{qw/id preference_id usr_pref prof_pref dom_pref peer_pref reseller_pref contract_pref contract_location_pref/};
                $efields->{default_val} = JSON::Types::bool($efields->{default_val});
                push @{ $fields->{enum_values} }, $efields;
            }
        }
        if ($pref->attribute =~ m/^(cdr_export_sclidui_rwrs|rewrite_rule_set|ncos|adm_ncos|adm_cf_ncos|emergency_mapping_container|sound_set|contract_sound_set|header_rule_set)$/) {
            $fields->{data_type} = 'string';
        }

        my $preference_group = $pref->voip_preference_group->name =~ s/([\[\]])/~$1/rg;
        my $label = $fields->{label} =~ s/([\[\]])/~$1/rg;
        my $description = $fields->{description} =~ s/([\[\]])/~$1/rg;
        $fields->{preference_group} = $c->loc($preference_group);
        $fields->{label} = $c->loc($label);
        $fields->{description} = $c->loc($description);
        $resource->{$pref->attribute} = $fields;
    }
    return $resource;
}

sub get_subscriber_allowed_prefs {
    my %params = @_;

    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my $prov_subs = $params{prov_subscriber};
    my $pref_list = $params{pref_list};

    my %allowed_prefs = map {$_ => 1} @{ $pref_list };

    if ($c->user->roles eq "subscriber" || $c->user->roles eq "subscriberadmin") {
        if ($prov_subs && $prov_subs->voip_subscriber_profile) {
            my $profile = $prov_subs->voip_subscriber_profile;
            my @result = $profile->profile_attributes->search_rs({
                'attribute.attribute' => { '-in' => $pref_list },
            },{
                join => 'attribute'
            })->get_column('attribute.attribute')->all;
            %allowed_prefs = map {$_ => 1} @result;
        }

    }

    return \%allowed_prefs
}

sub create_dynamic_preference {
    my ($c, $resource, %params) = @_;

    my $group_name = $params{group_name};
    my $relations = {};

    $resource->{voip_preference_groups_id} = $c->model('DB')
        ->resultset('voip_preference_groups')->find({name => $group_name})->id;
    $resource->{attribute} = dynamic_pref_attribute_to_db($resource->{attribute});
    $resource->{dynamic}   = 1;
    $resource->{internal}  = 0;
    $resource->{expose_to_customer} = 1;

    $relations->{autoprov_device_id} = delete $resource->{autoprov_device_id};
    $relations->{reseller_id} = delete $resource->{reseller_id};

    my $enums = delete $resource->{enum};
    my $preference = $c->model('DB')->resultset('voip_preferences')->create($resource);
    my @flags = grep {$_ =~/^[a-z]+_pref$/} keys %$resource;
    if(defined $enums and ref $enums eq 'ARRAY'){
        foreach my $enum (@$enums) {
            @{$enum}{@flags} = (1) x @flags;
            $preference->create_related('voip_preferences_enums', $enum);
        }
    }

    save_dynamic_preference_relations($c, $resource, $preference, $relations);

    return $preference;
}

sub update_dynamic_preference {
    my ($c, $preference, $resource, %params) = @_;

    my $relations = {};

    $resource->{attribute} = dynamic_pref_attribute_to_db($resource->{attribute});

    $relations->{autoprov_device_id} = delete $resource->{autoprov_device_id};
    $relations->{reseller_id} = delete $resource->{reseller_id};

    my $enums = delete $resource->{enum};

    $preference->update($resource);
    my @flags = grep {$_ =~/^[a-z]+_pref$/} keys %$resource;
    if(defined $enums and ref $enums eq 'ARRAY'){
        my $enums_rs = $preference->voip_preferences_enums;
        $enums_rs->search_rs({
            id => { -not_in => [ map { $_->{id} } @$enums ] },
        })->delete;
        foreach my $enum (@$enums) {
            my $id = delete $enum->{id};
            my $enum_exists = $enums_rs->find($id);
            @{$enum}{@flags} = (1) x @flags;
            if ($enum_exists) {
                $enum_exists->update($enum);
            } else {
                $preference->create_related('voip_preferences_enums', $enum);
            }
        }
    } else {
        $preference->voip_preferences_enums->delete;
    }

    save_dynamic_preference_relations($c, $resource, $preference, $relations);

    return $preference;
}

sub delete_dynamic_preference {
    my ($c, $preference) = @_;
    $preference->voip_preferences_enums->delete;
    $preference->delete;
}

sub save_dynamic_preference_relations {
    my ($c, $resource, $preference, $relations) = @_;

    if (defined $resource->{dev_pref} && $resource->{dev_pref}) {
        if ($relations->{autoprov_device_id}) {
            $preference->search_related_rs('voip_preference_relations')->update_or_create({
                autoprov_device_id => $relations->{autoprov_device_id},
                reseller_id        => undef,
            });
        } elsif ($relations->{reseller_id}) {
            $preference->search_related_rs('voip_preference_relations')->update_or_create({
                autoprov_device_id => undef,
                reseller_id => $relations->{reseller_id},
            });
        }
    }
}

sub dynamic_pref_attribute_to_standard {
    my ($attribute) = @_;
    $attribute =~s/^_*//;
    return $attribute;
}

sub dynamic_pref_attribute_to_db {
    my ($attribute) = @_;
    $attribute =~s/^_*/_DYNAMIC_PREFERENCE_PREFIX/e;
    return $attribute;
}

sub get_blob_short_value_size {
    return $blob_short_value_size;
}

1;

=head1 NAME

NGCP::Panel::Utils::Preferences

=head1 DESCRIPTION

Various utils to outsource common tasks in the controllers
regarding voip_preferences.

=head1 METHODS

=head2 load_preference_list

Parameters:
    c - set this to $c
    pref_values - hashref with all values (from voip_x_preferences)
    peer_pref - boolean, only select peer_prefs
    dom_pref - boolean, only select dom_prefs
    usr_pref - boolean, only select dom_prefs

Load preferences and groups. Fill them with pref_values.
Put them to stash as "pref_groups". This will be used in F<helpers/pref_table.tt>.

Also see "Special case rewrite_rule_set" and "Special case ncos and adm_ncos".

=head2 create_preference_form

Parameters:
    c - set this to $c
    pref_rs - a resultset for voip_x_preferences with the specific "x" already set
    enums - arrayref of all relevant enum rows (already filtered by eg. dom_pref)
    base_uri - string, uri of the preferences list
    edit_uri - string, uri to show the preferences edit modal

Use preference and preference_meta from stash and create a form. Process that
form in case the request has be POSTed. Also parse the GET params "delete",
"activate" and "deactivate" in order to operate on maxoccur != 1 preferences.
Put the form to stash as "form".

=head3 Special case rewrite_rule_set

In order to display the preference rewrite_rule_set correctly, the calling
controller must put rwr_sets_rs (as DBIx::Class::ResultSet) and rwr_sets
(for rendering in the template) to stash. A html select will then be displayed
with all the rewrite_rule_sets. Also helper.rewrite_rule_sets needs to be
set in the template (to be used by F<helpers/pref_table.tt>).

On update 4 voip_*_preferences will be created with the attributes
rewrite_callee_in_dpid, rewrite_caller_in_dpid, rewrite_callee_out_dpid,
rewrite_caller_out_dpid, rewrite_callee_lnp_dpid, rewrite_caller_lnp_dpid
(using the helper method set_rewrite_preferences).

For compatibility with ossbss and the www_admin panel, no preference with
the attribute rewrite_rule_set is created and caller_in_dpid is used to
check which rewrite_rule_set is currently set.

=head3 Special case ncos and adm_ncos

Very similar to rewrite_rule_set (see above). The stashed variables are
ncos_levels_rs and ncos_levels. In the template helper.ncos_levels needs to
be set.

The updated preferences are called ncos_id and adm_ncos_id.

=head3 Special case emergency_mapping_container

Very similar to ncos (see above). The stashed variables are
emergency_mapping_containers_rs and emergency_mapping_containers. In the template
helper.ncos_levels needs to be set.

The updated preferences are called ncos_id and adm_ncos_id.

=head3 Special case sound_set and contract_sound_set

This is also similar to rewrite_rule_set and ncos. The stashed variables are
(contract_)sound_sets_rs and (contract_)sound_sets. In the template helper.(contract_)sound_sets needs to
be set.

The preference with the attribute (contract_)sound_set will contain the id of a sound set.

=head3 Special case allowed_ips

Also something special here. The table containing data is
provisioning.voip_allowed_ip_groups.

=head2 set_rewrite_preferences

See "Special case rewrite_rule_set".

=head1 AUTHOR

Andreas Granig,
Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
