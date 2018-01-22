package NGCP::Panel::Utils::Preferences;

use Sipwise::Base;

use Data::Validate::IP qw/is_ipv4 is_ipv6/;
use NGCP::Panel::Form::Preferences;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::I18N qw//;
use NGCP::Panel::Utils::Sems;

use constant _DYNAMIC_PREFERENCE_PREFIX => '__';

sub validate_ipnet {
    my ($field) = @_;
    my ($ip, $net) = split /\//, $field->value;
    if(is_ipv4($ip)) {
        return 1 unless(defined $net);
        unless(is_int($net) && $net >= 0 && $net <= 32) {
            $field->add_error("Invalid IPv4 network portion, must be 0 <= net <= 32");
            return;
        }
    } elsif(is_ipv6($ip)) {
        return 1 unless(defined $net);
        unless(is_int($net) && $net >= 0 && $net <= 128) {
            $field->add_error("Invalid IPv6 network portion, must be 0 <= net <= 128");
            return;
        }
    } else {
        $field->add_error("Invalid IPv4 or IPv6 address, must be valid address with optional /net suffix.");
        return;
    }
    return 1;
}

sub load_preference_list {
    my %params = @_;

    my $c = $params{c};
    my $pref_values = $params{pref_values};
    my $peer_pref = $params{peer_pref};
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
                        caller_in_dpid =>$pref_values->{rewrite_caller_in_dpid}
                    })->first) ?
                    $tmp->id
                    : undef;
            }
            elsif($pref->attribute eq "ncos") {
                if ($pref_values->{ncos_id} &&
                    (my $tmp = $c->stash->{ncos_levels_rs}
                        ->find($pref_values->{ncos_id}) )) {
                    $pref->{ncos_id} = $tmp->id;
                }
            }
            elsif($pref->attribute eq "adm_ncos") {
                if ($pref_values->{adm_ncos_id} &&
                    (my $tmp = $c->stash->{ncos_levels_rs}
                        ->find($pref_values->{adm_ncos_id}) )) {
                    $pref->{adm_ncos_id} = $tmp->id;
                }
            }
            elsif($pref->attribute eq "adm_cf_ncos") {
                if ($pref_values->{adm_cf_ncos_id} &&
                    (my $tmp = $c->stash->{ncos_levels_rs}
                        ->find($pref_values->{adm_cf_ncos_id}) )) {
                    $pref->{adm_cf_ncos_id} = $tmp->id;
                }
            }
            elsif($pref->attribute eq "emergency_mapping_container") {
                if ($pref_values->{emergency_mapping_container_id} &&
                    (my $tmp = $c->stash->{emergency_mapping_containers_rs}
                        ->find($pref_values->{emergency_mapping_container_id}) )) {
                    $pref->{emergency_mapping_container_id} = $tmp->id;
                }
            }
            elsif($pref->attribute eq "allowed_ips") {
                $pref->{allowed_ips_group_id} = $pref_values->{allowed_ips_grp};
                $pref->{allowed_ips_rs} = $c->model('DB')->resultset('voip_allowed_ip_groups')
                    ->search_rs({ group_id => $pref_values->{allowed_ips_grp} });
            }
            elsif($pref->attribute eq "man_allowed_ips") {
                $pref->{man_allowed_ips_group_id} = $pref_values->{man_allowed_ips_grp};
                $pref->{man_allowed_ips_rs} = $c->model('DB')->resultset('voip_allowed_ip_groups')
                    ->search_rs({ group_id => $pref_values->{man_allowed_ips_grp} });
            }
            elsif($c->stash->{subscriber} &&
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
            $preselected_value = $c->stash->{preference}->first->value;
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

sub set_rewrite_preferences {
    my %params = @_;

    my $c             = $params{c};
    my $rwrs_result   = $params{rwrs_result};
    my $pref_rs       = $params{pref_rs};

    for my $rules(qw/
                    callee_in_dpid caller_in_dpid
                    callee_out_dpid caller_out_dpid
                    callee_lnp_dpid caller_lnp_dpid/) {

        my $attribute_id = $c->model('DB')->resultset('voip_preferences')
            ->find({attribute => "rewrite_$rules"})->id;
        my $preference = $pref_rs->search({
            attribute_id => $attribute_id,
        });

        if(!defined $rwrs_result) {
            $preference->first->delete if $preference->first;
        } elsif($preference->first) {
            $preference->first->update({ value => $rwrs_result->$rules });
        } else {
            $preference->create({ value => $rwrs_result->$rules });
        }
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

    # filter by allowed attrs from profile
    if ($is_subadmin && $prov_subscriber && $prov_subscriber->voip_subscriber_profile) {
        my $found_attr = $prov_subscriber->voip_subscriber_profile
            ->profile_attributes->search_rs({
                attribute_id => $pref_rs->id,
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
    my ($c, $prov_subscriber, $old_auth_prefs, $new_auth_prefs) = @_;

    if(!_is_peer_auth_active($c, $old_auth_prefs) &&
        _is_peer_auth_active($c, $new_auth_prefs)) {

        NGCP::Panel::Utils::Sems::create_peer_registration(
            $c, $prov_subscriber, $new_auth_prefs);
    } elsif( _is_peer_auth_active($c, $old_auth_prefs) &&
            !_is_peer_auth_active($c, $new_auth_prefs)) {

        NGCP::Panel::Utils::Sems::delete_peer_registration(
            $c, $prov_subscriber, $old_auth_prefs);
    } elsif(_is_peer_auth_active($c, $old_auth_prefs) &&
            _is_peer_auth_active($c, $new_auth_prefs)){

        NGCP::Panel::Utils::Sems::update_peer_registration(
            $c, $prov_subscriber, $new_auth_prefs, $old_auth_prefs);
    }

    return;
}

sub get_peer_auth_params {
    my ($c, $prov_subscriber, $prefs) = @_;

    foreach my $attribute (qw/peer_auth_user peer_auth_realm peer_auth_pass peer_auth_register/){
        my $rs;
        $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
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

    my $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
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

    my $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
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

sub api_preferences_defs{
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
        delete @{$fields}{qw/type attribute expose_to_customer internal peer_pref usr_pref dom_pref contract_pref contract_location_pref prof_pref voip_preference_groups_id id modify_timestamp/};
        $fields->{max_occur} = int($fields->{max_occur});
        $fields->{read_only} = JSON::Types::bool($fields->{read_only});
        if($fields->{data_type} eq "enum") {
            my @enums = $pref->voip_preferences_enums->search({
                $preferences_group => 1,
            })->all;
            $fields->{enum_values} = [];
            foreach my $enum(@enums) {
                my $efields = { $enum->get_inflated_columns };
                delete @{$efields}{qw/id preference_id usr_pref prof_pref dom_pref peer_pref contract_pref contract_location_pref/};
                $efields->{default_val} = JSON::Types::bool($efields->{default_val});
                push @{ $fields->{enum_values} }, $efields;
            }
        }
        if ($pref->attribute =~ m/^(rewrite_rule_set|ncos|adm_ncos|adm_cf_ncos|emergency_mapping_container|sound_set|contract_sound_set|header_rule_set)$/) {
            $fields->{data_type} = 'string';
        }
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
