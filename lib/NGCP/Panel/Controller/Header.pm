package NGCP::Panel::Controller::Header;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Rewrite;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::HeaderManipulations;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    my $ngcp_type = $c->config->{general}{ngcp_type} // '';
    if ($ngcp_type ne 'sppro' && $ngcp_type ne 'carrier') {
        $c->detach('/error_page');
    }
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub set_list :Chained('/') :PathPart('header') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{hm_sets_rs} = $c->model('DB')->resultset('voip_header_rule_sets')->search({
        subscriber_id => undef
    });
    unless($c->user->roles eq "admin") {
        $c->stash->{hm_sets_rs} = $c->stash->{hm_sets_rs}->search({
            reseller_id => $c->user->reseller_id
        });
    }
    $c->stash->{hm_set_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ]);

    $c->stash(template => 'header/set_list.tt');
}

sub set_root :Chained('set_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub set_ajax :Chained('set_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{hm_sets_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{hm_set_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub set_base :Chained('set_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    unless($set_id && is_int($set_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid header rule set id detected',
            desc  => $c->loc('Invalid header rule set id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }

    my $res = $c->stash->{hm_sets_rs}->find($set_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Header rule set does not exist',
            desc  => $c->loc('Header rule set does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }
    $c->stash(hm_set_result => $res);
}

sub set_edit :Chained('set_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{hm_set_result}->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::AdminRuleSet", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ResellerRuleSet", $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                delete $form->values->{reseller};
            }
            $c->stash->{hm_set_result}->update($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $c->stash->{hm_set_result}->id
            );
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule set successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update header rule set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub set_delete :Chained('set_base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        my $set_id = $c->stash->{hm_set_result}->id;
        $c->stash->{hm_set_result}->delete;
        NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
            c => $c, set_id => $set_id
        );
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{hm_set_result}->get_inflated_columns },
            desc => $c->loc('Header rule set successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete header rule set'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
}

sub set_clone :Chained('set_base') :PathPart('clone') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{hm_set_result}->get_inflated_columns };
    $params = merge($params, $c->session->{created_objects});
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::CloneRuleSet", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $new_set = $c->stash->{hm_sets_rs}->create({
                    %{ $form->values }, ## no critic (ProhibitCommaSeparatedStatements)
                    reseller_id => $c->stash->{hm_set_result}->reseller_id,
                });
                my @old_rules = $c->stash->{hm_set_result}->voip_header_rules->all;
                for my $rule (@old_rules) {
                    $new_set->voip_rewrite_rules->create({
                        match_pattern => $rule->match_pattern,
                        replace_pattern => $rule->replace_pattern,
                        description => $rule->description,
                        direction => $rule->direction,
                        field => $rule->field,
                        priority => $rule->priority,
                        enabled => $rule->enabled,
                    });
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule set successfully cloned'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to clone header rule set.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
    $c->stash(clone_flag => 1);
}

sub set_create :Chained('set_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::AdminRuleSet", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ResellerRuleSet", $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                delete $form->values->{reseller};
            } else {
                $form->values->{reseller_id} = $c->user->reseller_id;
            }
            $c->stash->{hm_sets_rs}->create($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule set successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create header rule set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub rules_list :Chained('set_base') :PathPart('rules') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    NGCP::Panel::Utils::HeaderManipulations::ui_rules_list(
        c => $c
    );

    $c->stash(hm_rules_uri => $c->uri_for_action("/header/rules_root", [$c->req->captures->[0]]));
    $c->stash(template => 'header/rules_list.tt');
    return;
}

sub rules_root :Chained('rules_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_rules_root(
        c => $c
    );
}

sub rules_ajax :Chained('rules_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_rules_ajax(
        c => $c
    );
}

sub rules_base :Chained('rules_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $rule_id) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_rules_base(
        c => $c, rule_id => $rule_id
    );
}

sub rules_edit :Chained('rules_base') :PathPart('edit') {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_rules_edit(
        c => $c
    );
}

sub rules_delete :Chained('rules_base') :PathPart('delete') {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_rules_delete(
        c => $c
    );
}

sub rules_create :Chained('rules_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_rules_create(
        c => $c
    );
}

sub conditions_list :Chained('rules_base') :PathPart('conditions') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    NGCP::Panel::Utils::HeaderManipulations::ui_conditions_list(
        c => $c
    );

    $c->stash(hm_conditions_uri => $c->uri_for_action("/header/conditions_root", $c->req->captures));
    $c->stash(template => 'header/conditions_list.tt');
    return;
}

sub conditions_root :Chained('conditions_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_conditions_root(
        c => $c
    );
}

sub conditions_ajax :Chained('conditions_list') :PathPart('rules_ajax') :Args(0) {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_conditions_ajax(
        c => $c
    );
}

sub conditions_base :Chained('conditions_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $condition_id) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_conditions_base(
        c => $c, condition_id => $condition_id
    );
}

sub conditions_edit :Chained('conditions_base') :PathPart('edit') {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_conditions_edit(
        c => $c
    );
}

sub conditions_delete :Chained('conditions_base') :PathPart('delete') {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_conditions_delete(
        c => $c
    );
}

sub conditions_create :Chained('conditions_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_conditions_create(
        c => $c
    );
}

sub actions_list :Chained('rules_base') :PathPart('actions') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    NGCP::Panel::Utils::HeaderManipulations::ui_actions_list(
        c => $c
    );

    $c->stash(hm_actions_uri => $c->uri_for_action("/header/actions_root", $c->req->captures));
    $c->stash(template => 'header/actions_list.tt');
    return;
}

sub actions_root :Chained('actions_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_actions_root(
        c => $c
    );
}

sub actions_ajax :Chained('actions_list') :PathPart('rules_ajax') :Args(0) {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_actions_ajax(
        c => $c
    );
}

sub actions_base :Chained('actions_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $action_id) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_actions_base(
        c => $c, action_id => $action_id
    );
}

sub actions_edit :Chained('actions_base') :PathPart('edit') {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_actions_edit(
        c => $c
    );
}

sub actions_delete :Chained('actions_base') :PathPart('delete') {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_actions_delete(
        c => $c
    );
}

sub actions_create :Chained('actions_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    return NGCP::Panel::Utils::HeaderManipulations::ui_actions_create(
        c => $c
    );
}

1;

=head1 NAME

NGCP::Panel::Controller::Header - Manage Header Rules

=head1 DESCRIPTION

Show/Edit/Create/Delete Header Rule Sets.

Show/Edit/Create/Delete Header Rules within Header Rule Sets.

=head1 METHODS

=head2 set_list

Basis for provisioning.voip_rewrite_rule_sets.

=head2 set_root

Display rewrite rule sets through F<rewrite/set_list.tt> template.

=head2 set_ajax

Get provisioning.voip_rewrite_rule_sets from the database and
output them as JSON.
The format is meant for parsing with datatables.

=head2 set_base

Fetch a provisioning.voip_rewrite_rule_set from the database by its id.

=head2 set_edit

Show a modal to edit a rewrite rule set determined by L</set_base>.
The form used is L<NGCP::Panel::Form::RewriteRuleSet>.

=head2 set_delete

Delete a rewrite rule set determined by L</set_base>.

=head2 set_clone

Deep copy a rewrite rule set determined by L</set_base>. The user can enter
a new name and description. The reseller is not configurable, but set by the
original rewrite rule set. The rewrite rules of the original rwrs are then
cloned and assigned to the new rwrs.

=head2 set_create

Show a modal to create a new rewrite rule set using the form
L<NGCP::Panel::Form::RewriteRuleSet>.

=head2 rules_list

Basis for provisioning.voip_rewrite_rules. Chained from L</set_base> and
therefore handles only rules for a certain rewrite rule set.

=head2 rules_root

Display rewrite rule sets through F<rewrite/rules_list.tt> template.
The rules are stashed to rules hashref which contains the keys
"caller_in", "callee_in", "caller_out", "callee_out".

It swaps priority of two elements if "move" and "where" GET params are set.

It modifies match_pattern and replace_pattern field to a certain output format
using regex.

=head2 rules_base

Fetch a rewrite rule from the database by its id. Will only find rules under
the current rule_set.

=head2 rules_edit

Show a modal to edit a rewrite rule determined by L</rules_base>.
The form used is L<NGCP::Panel::Form::RewriteRule>.

=head2 rules_delete

Delete a rewrite rule determined by L</rules_base>.

=head2 rules_create

Show a modal to create a new rewrite rule using the form
L<NGCP::Panel::Form::RewriteRule>.

=head2 _sip_dialplan_reload

This is ported from ossbss.

Reloads dialplan cache of sip proxies.

=head1 AUTHOR

Sipwise Development Team C<< <support@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
