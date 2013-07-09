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
        ->search({ 'voip_preferences.internal' => 0,
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

    my $form = NGCP::Panel::Form::Preferences->new({
        fields_data => [{
            meta => $c->stash->{preference_meta},
            enums => $enums,
        }],
    });
    $form->create_structure([$c->stash->{preference_meta}->attribute]);

    my $posted = ($c->request->method eq 'POST');
    if($c->stash->{preference_meta}->max_occur == 1){
        $form->process(
            posted => 1,
            params => $posted ? $c->request->params : { $c->stash->{preference_meta}->attribute => $c->stash->{preference_values}->[0] },
            action => $edit_uri,
        );
    } else {
        $form->process(
            posted => 1,
            params => $posted ? $c->request->params : {},
            action => $edit_uri,
        );
    }
    if($posted && $form->validated) {
        my $preference_id = $c->stash->{preference}->first ? $c->stash->{preference}->first->id : undef;
        if ($c->stash->{preference_meta}->max_occur != 1) {
            $pref_rs->create({
                attribute_id => $c->stash->{preference_meta}->id,
                value => $form->field($c->stash->{preference_meta}->attribute)->value,
            });
        } else {
            $pref_rs->update_or_create({
                id => $preference_id,
                attribute_id => $c->stash->{preference_meta}->id,
                value => $form->field($c->stash->{preference_meta}->attribute)->value,
            });
            $c->flash(messages => [{type => 'success', text => 'Preference '.$c->stash->{preference_meta}->attribute.' successfully updated.'}]);
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

=head1 AUTHOR

Andreas Granig,
Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
