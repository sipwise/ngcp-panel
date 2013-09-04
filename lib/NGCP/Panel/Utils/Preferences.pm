package NGCP::Panel::Utils::Preferences;
use strict;
use warnings;

use NGCP::Panel::Form::Preferences;

sub load_preference_list {
    my %params = @_;

    my $c = $params{c};
    my $pref_values = $params{pref_values};
    my $peer_pref = $params{peer_pref};
    my $dom_pref = $params{dom_pref};
    my $usr_pref = $params{usr_pref};
    
    my @pref_groups = $c->model('DB')
        ->resultset('voip_preference_groups')
        ->search({ 'voip_preferences.internal' => { '<=' => 0 },
            $peer_pref ? ('voip_preferences.peer_pref' => 1,
                -or => ['voip_preferences_enums.peer_pref' => 1,
                    'voip_preferences_enums.peer_pref' => undef]) : (),
            $dom_pref ? ('voip_preferences.dom_pref' => 1,
                -or => ['voip_preferences_enums.dom_pref' => 1,
                    'voip_preferences_enums.dom_pref' => undef]) : (),
            $usr_pref ? ('voip_preferences.usr_pref' => 1,
                -or => ['voip_preferences_enums.usr_pref' => 1,
                    'voip_preferences_enums.usr_pref' => undef]) : (),
            }, {
                prefetch => {'voip_preferences' => 'voip_preferences_enums'},
            })
        ->all;

    foreach my $group(@pref_groups) {
        my @group_prefs = $group->voip_preferences->all;
        
        foreach my $pref(@group_prefs) {
            if($pref->attribute eq "rewrite_rule_set") {
                $pref->{rwrs_id} = $pref_values->{rewrite_caller_in_dpid} ?
                    $c->stash->{rwr_sets_rs}->search({
                        caller_in_dpid =>$pref_values->{rewrite_caller_in_dpid}
                    })->first->id
                    : undef;
            }
            elsif($pref->attribute eq "ncos") {
                $pref->{ncos_id} = $pref_values->{ncos_id} ?
                    $c->stash->{ncos_levels_rs}
                        ->find($pref_values->{ncos_id})->id
                    : undef;
            }
            elsif($pref->attribute eq "adm_ncos") {
                $pref->{adm_ncos_id} = $pref_values->{adm_ncos_id} ?
                    $c->stash->{ncos_levels_rs}
                        ->find($pref_values->{adm_ncos_id})->id
                    : undef;
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
            if($pref->data_type eq "enum") {
                $pref->{enums} = [];
                push @{ $pref->{enums} },
                    $pref->voip_preferences_enums->all;
            }
            my @values = @{
                exists $pref_values->{$pref->attribute}
                    ? $pref_values->{$pref->attribute}
                    : []
            };
            next unless(scalar @values);
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

    my $preselected_value = undef;
    if ($c->stash->{preference_meta}->attribute eq "rewrite_rule_set") {
        my $rewrite_caller_in_dpid = $pref_rs->search({
                'attribute.attribute' => 'rewrite_caller_in_dpid'
            },{
                join => 'attribute'
            })->first;
        if (defined $rewrite_caller_in_dpid) {
            $preselected_value = $c->stash->{rwr_sets_rs}->search({
                    caller_in_dpid => $rewrite_caller_in_dpid->value,
                })->first->id;
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
    } elsif ($c->stash->{preference_meta}->max_occur == 1) {
        $preselected_value = $c->stash->{preference_values}->[0];
    }

    my $form = NGCP::Panel::Form::Preferences->new({
        fields_data => [{
            meta => $c->stash->{preference_meta},
            enums => $enums,
            rwrs_rs => $c->stash->{rwr_sets_rs},
            ncos_rs => $c->stash->{ncos_levels_rs},
            sound_rs => $c->stash->{sound_sets_rs},
        }],
    });
    $form->create_structure([$c->stash->{preference_meta}->attribute]);

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
    if($posted && $form->validated) {
        my $preference_id = $c->stash->{preference}->first ? $c->stash->{preference}->first->id : undef;
        my $attribute = $c->stash->{preference_meta}->attribute;
       if ($attribute eq "allowed_ips") {

            unless (defined $aip_group_id) {
                #TODO put this in a transaction
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
            }
            $aip_grp_rs->create({
                group_id => $aip_group_id,
                ipnet => $form->field($attribute)->value,
            });
       } elsif ($attribute eq "man_allowed_ips") {

            unless (defined $man_aip_group_id) {
                #TODO put this in a transaction
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
            }
            $man_aip_grp_rs->create({
                group_id => $man_aip_group_id,
                ipnet => $form->field($attribute)->value,
            });
        } elsif ($c->stash->{preference_meta}->max_occur != 1) {
            $pref_rs->create({
                attribute_id => $c->stash->{preference_meta}->id,
                value => $form->field($c->stash->{preference_meta}->attribute)->value,
            });
        } elsif ($attribute eq "rewrite_rule_set") {
            my $selected_rwrs = $c->stash->{rwr_sets_rs}->find(
                $form->field($attribute)->value
            );
            set_rewrite_preferences(
                c             => $c,
                rwrs_result   => $selected_rwrs,
                pref_rs       => $pref_rs,
            );
            $c->flash(messages => [{type => 'success', text => "Preference $attribute successfully updated."}]);
            $c->response->redirect($base_uri);
            return;
        } elsif ($attribute eq "ncos" || $attribute eq "adm_ncos") {
            my $selected_level = $c->stash->{ncos_levels_rs}->find(
                $form->field($attribute)->value
            );
            my $attribute_id = $c->model('DB')->resultset('voip_preferences')
                ->find({attribute => $attribute."_id"})->id;


            my $preference = $pref_rs->search({ attribute_id => $attribute_id });
            if(!defined $selected_level) {
                $preference->first->delete if $preference->first;
            } elsif($preference->first) {
                $preference->first->update({ value => $selected_level->id });
            } else {
                $preference->create({ value => $selected_level->id });
            }

            $c->flash(messages => [{type => 'success', text => "Preference $attribute successfully updated."}]);
            $c->response->redirect($base_uri);
            return;
        } elsif ($attribute eq "sound_set") {
            my $selected_set = $c->stash->{sound_sets_rs}->find(
                $form->field($attribute)->value
            );

            my $preference = $pref_rs->search({
                attribute_id => $c->stash->{preference_meta}->id });
            if(!defined $selected_set) {
                $preference->first->delete if $preference->first;
            } elsif($preference->first) {
                $preference->first->update({ value => $selected_set->id });
            } else {
                $preference->create({ value => $selected_set->id });
            }

            $c->flash(messages => [{type => 'success', text => "Preference $attribute successfully updated."}]);
            $c->response->redirect($base_uri);
            return;
        } else {
            if($form->field($attribute)->value eq '') {
                my $preference = $pref_rs->find($preference_id);
                $preference->delete if $preference;
            } elsif($c->stash->{preference_meta}->data_type eq 'boolean' && 
                    $form->field($attribute)->value == 0) {
                my $preference = $pref_rs->find($preference_id);
                $preference->delete if $preference;
            } else {
                $pref_rs->update_or_create({
                    id => $preference_id,
                    attribute_id => $c->stash->{preference_meta}->id,
                    value => $form->field($attribute)->value,
                });
            }
            $c->flash(messages => [{type => 'success', text => "Preference $attribute successfully updated."}]);
            $c->response->redirect($base_uri);
            return;
         }
    }
    
    my $delete_param = $c->request->params->{delete};
    my $deactivate_param = $c->request->params->{deactivate};
    my $activate_param = $c->request->params->{activate};
    my $param_id = $delete_param || $deactivate_param || $activate_param;
    # only one parameter is processed at a time (?)
    if($param_id) {
        my $rs = $pref_rs->find($param_id);
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

    $form->process if ($posted && $form->validated);
    $c->stash(form       => $form,
              aip_grp_rs => $aip_grp_rs,
              man_aip_grp_rs => $man_aip_grp_rs);
}

sub set_rewrite_preferences {
    my %params = @_;

    my $c             = $params{c};
    my $rwrs_result   = $params{rwrs_result};
    my $pref_rs       = $params{pref_rs};

    for my $rules ("callee_in_dpid", "caller_in_dpid",
                 "callee_out_dpid", "caller_out_dpid") {

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

sub get_usr_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $prov_subscriber= $params{prov_subscriber};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'usr_pref' => 1,
        })->voip_usr_preferences->search_rs({
            subscriber_id => $prov_subscriber->id,
        });
    return $preference;
}

sub get_dom_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $prov_domain = $params{prov_domain};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'dom_pref' => 1,
        })->voip_usr_preferences->search_rs({
            domain_id => $prov_domain->id,
        });
    return $preference;
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
rewrite_callee_in_dpid, rewrite_caller_in_dpid, rewrite_callee_out_dpid
and rewrite_caller_out_dpid (using the helper method set_rewrite_preferences).

For compatibility with ossbss and the www_admin panel, no preference with
the attribute rewrite_rule_set is created and caller_in_dpid is used to
check which rewrite_rule_set is currently set.

=head3 Special case ncos and adm_ncos

Very similar to rewrite_rule_set (see above). The stashed variables are
ncos_levels_rs and ncos_levels. In the template helper.ncos_levels needs to
be set.

The updated preferences are called ncos_id and adm_ncos_id.

=head3 Special case sound_set

This is also similar to rewrite_rule_set and ncos. The stashed variables are
sound_sets_rs and sound_sets. In the template helper.sound_sets needs to
be set.

The preference with the attribute sound_set will contain the id of a sound_set.

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
