package NGCP::Panel::Role::API::HeaderRules;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::API;
use NGCP::Panel::Utils::HeaderManipulations;
use HTTP::Status qw(:constants);

sub item_name {
    return 'headerrule';
}

sub resource_name {
    return 'headerrules';
}

sub config_allowed_roles {
    return [qw/admin reseller/];
}

sub _item_rs {
    my ($self, $c, $type) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_header_rules')->search_rs(undef, {
        join => 'ruleset'
    });


    if ($c->user->roles eq "reseller") {
        $item_rs = $c->model('DB')->resultset('voip_header_rules')->search_rs({
            'ruleset.reseller_id' => $c->user->reseller_id,
        });
    }

    if (my $subscriber_id = $c->req->param('subscriber_id')) {
        my $prov_subscriber_id = NGCP::Panel::Utils::Subscriber::billing_to_prov_subscriber_id(
            c => $c, subscriber_id => $subscriber_id
        );
        $item_rs = $item_rs->search_rs(
            { 'ruleset.subscriber_id' => $prov_subscriber_id });
    } else {
        $item_rs = $item_rs->search_rs(
            { 'ruleset.subscriber_id' => undef });
    }

    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return ( NGCP::Panel::Form::get("NGCP::Panel::Form::Header::RuleAPI", $c) );
}

sub hal_links {
    my ($self, $c, $item, $resource, $form) = @_;
    return [
        Data::HAL::Link->new(relation => "ngcp:headerrulesets", href => sprintf("/api/headerrulesets/%d", $item->set_id)),
    ];
}

sub check_resource {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

    unless (defined $resource->{set_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required: 'set_id'");
        return;
    }

    my $reseller_id;
    if ($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }

    my $ruleset = $schema->resultset('voip_header_rule_sets')->find({
        id => $resource->{set_id},
        ($reseller_id ? (reseller_id => $reseller_id) : ()),
    });
    unless ($ruleset) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'set_id'.");
        return;
    }

    $c->stash->{checked}->{ruleset} = $ruleset;

    return 1;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $header_actions = delete $resource->{actions};
    my $header_conditions = delete $resource->{conditions};
    $item->update($resource);
    if ($header_actions) {
        $item->actions->delete;
        foreach my $action (@$header_actions) {
            $action->{rule_id} = $item->id;
            last unless $self->validate_form(
                c => $c,
                resource => $action,
                form => (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ActionAPI", $c)),
            );
            last unless NGCP::Panel::Role::API::HeaderRuleActions->check_resource($c, undef, undef, $action, undef, undef);
            my $action_result = $item->actions->create($action);
        }
    }
    if ($header_conditions) {
        $item->conditions->delete;
        foreach my $condition (@$header_conditions) {
            $condition->{rule_id} = $item->id;
            last unless $self->validate_form(
                c => $c,
                resource => $condition,
                form => (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ConditionAPI", $c)),
            );
            last unless NGCP::Panel::Role::API::HeaderRuleConditions->check_resource($c, undef, undef, $condition, undef, undef);
            my $condition_result = $item->conditions->create($condition);
        }
    }

    NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
        c => $c, set_id => $item->ruleset->id
    );

    return $item;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = $item->get_inflated_columns;

    my @actions = map { {$_->get_inflated_columns} } $item->actions->all;
    my @conditions = map { {$_->get_inflated_columns} } $item->conditions->all;

    $resource{actions} = \@actions;
    $resource{conditions} = \@conditions;

    return \%resource;
}

1;
# vim: set tabstop=4 expandtab:
