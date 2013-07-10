package NGCP::Panel::Utils;
use strict;
use warnings;

use NGCP::Panel::Form::Preferences;

sub check_redirect_chain {
    my %params = @_;

    # TODO: check for missing fields
    my $c = $params{c};

    if($c->session->{redirect_targets} && @{ $c->session->{redirect_targets} }) {
        my $target = ${ $c->session->{redirect_targets} }[0];
        if('/'.$c->request->path eq $target->path) {
            shift @{$c->session->{redirect_targets}};
            $c->stash(close_target => ${ $c->session->{redirect_targets} }[0]);
        } else {
            $c->stash(close_target => $target);
        }
    }
}

sub check_form_buttons {
    my %params = @_;

    # TODO: check for missing fields
    my $c = $params{c};
    my $fields = $params{fields};
    my $form = $params{form};
    my $back_uri = $params{back_uri};
    
    $fields = { map {($_, undef)} @$fields }
        if (ref($fields) eq "ARRAY");

    my $posted = ($c->request->method eq 'POST');

    if($posted && $form->field('submitid')) {
        my $val = $form->field('submitid')->value;
    
        if(defined $val and exists($fields->{$val}) ) {
            my $target;
            if (defined $fields->{$val}) {
                $target = $fields->{$val};
            } else {
                $target = '/'.$val;
                $target =~ s/\./\//g;
                $target = $c->uri_for($target);
            }
            if($c->session->{redirect_targets}) {
                unshift @{ $c->session->{redirect_targets} }, $back_uri;
            } else {
                $c->session->{redirect_targets} = [ $back_uri ];
            }
            $c->response->redirect($target);
            return 1;
        }
    }
    return;
}

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
    } elsif ($c->stash->{preference_meta}->max_occur == 1) {
        $preselected_value = $c->stash->{preference_values}->[0];
    }

    $c->log->debug("Preselected value: $preselected_value");

    my $form = NGCP::Panel::Form::Preferences->new({
        fields_data => [{
            meta => $c->stash->{preference_meta},
            enums => $enums,
            rwrs_rs => $c->stash->{rwr_sets_rs},
            ncos_rs => $c->stash->{ncos_levels_rs},
        }],
    });
    $form->create_structure([$c->stash->{preference_meta}->attribute]);

    my $posted = ($c->request->method eq 'POST');
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : { $c->stash->{preference_meta}->attribute => $preselected_value },
        action => $edit_uri,
    );
    if($posted && $form->validated) {
        my $preference_id = $c->stash->{preference}->first ? $c->stash->{preference}->first->id : undef;
        my $attribute = $c->stash->{preference_meta}->attribute;
        if ($c->stash->{preference_meta}->max_occur != 1) {
            $pref_rs->create({
                attribute_id => $c->stash->{preference_meta}->id,
                value => $form->field($c->stash->{preference_meta}->attribute)->value,
            });
        } elsif ($attribute eq "rewrite_rule_set") {
            my $selected_rwrs = $c->stash->{rwr_sets_rs}->find(
                $form->field($attribute)->value
            );
            _set_rewrite_preferences(
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
            $pref_rs->update_or_create({
                attribute_id => $attribute_id,
            })->update({ value => $selected_level->id });
            $c->flash(messages => [{type => 'success', text => "Preference $attribute successfully updated."}]);
            $c->response->redirect($base_uri);
            return;
        } else {
            $pref_rs->update_or_create({
                id => $preference_id,
                attribute_id => $c->stash->{preference_meta}->id,
                value => $form->field($attribute)->value,
            });
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

    $c->stash(form => $form);
}

sub _set_rewrite_preferences {
    my %params = @_;

    my $c             = $params{c};
    my $rwrs_result   = $params{rwrs_result};
    my $pref_rs       = $params{pref_rs};

    for my $foo ("callee_in_dpid", "caller_in_dpid",
                 "callee_out_dpid", "caller_out_dpid") {

        my $attribute_id = $c->model('DB')->resultset('voip_preferences')
            ->find({attribute => "rewrite_$foo"})->id;
        my $preference = $pref_rs->search({
            attribute_id => $attribute_id,
        })->update_or_create({});
        $preference->update({ value => $rwrs_result->$foo });
    }

}

1;

=head1 NAME

NGCP::Panel::Utils

=head1 DESCRIPTION

Various utils to outsource common tasks in the controllers.

=head1 METHODS

=head2 check_redirect_chain

Sets close_target to the next uri in our redirect_chain if it exists.
Puts close_target to stash, which will be read by the templates.

=head2 check_form_buttons

Parameters:
    c
    fields - either an arrayref of fieldnames or a hashref with fieldnames
        key and redirect target as value (where it should redirect to)
    form
    back_uri - the uri we come from

Checks the hidden field "submitid" and redirects to its "value" when it
matches a field.

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
and rewrite_caller_out_dpid (using the helper method _set_rewrite_preferences).

For compatibility with ossbss and the www_admin panel, no preference with
the attribute rewrite_rule_set is created and caller_in_dpid is used to
check which rewrite_rule_set is currently set.

=head3 Special case ncos and adm_ncos

Very similar to rewrite_rule_set (see above). The stashed variables are
ncos_levels_rs and ncos_levels. In the template helper.ncos_levels needs to
be set.

The updated preferences are called ncos_id and adm_ncos_id.

=head2 _set_rewrite_preferences

See "Special case rewrite_rule_set".

=head1 AUTHOR

Andreas Granig,
Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
