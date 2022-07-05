package NGCP::Panel::Controller::API::HeaderRuleSets;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::HeaderRuleSets/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    allowed_ngcp_types => [qw/carrier sppro/],
});

sub allowed_methods {
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines header manipulation rule sets.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for header rule sets of a specific reseller',
            query_type => 'string_eq',
        },
        {
            param => 'subscriber_id',
            description => 'Filter for header rule sets of a specific subscriber',
            # no query_type is specified here on purpose
            # the filter applies in the _item_rs() instead
            # because the value is inflated there
        },
        {
            param => 'name',
            description => 'Filter for header rule sets with a specific name (wildcard pattern allowed)',
            query_type => 'string_like',
        },
        {
            param => 'description',
            description => 'Filter header rule sets for a certain description (wildcard pattern allowed).',
            query_type => 'string_like',
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item;
    my $schema = $c->model('DB');
    try {
        my $header_rules = delete $resource->{rules};
        $item = $schema->resultset('voip_header_rule_sets')->create($resource);
        if ($header_rules) {
            foreach my $rule (@$header_rules) {
                my $header_actions = delete $rule->{actions};
                my $header_conditions = delete $rule->{conditions};
                $rule->{set_id} = $item->id;
                last unless $self->validate_form(
                    c => $c,
                    resource => $rule,
                    form => (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::RuleAPI", $c)),
                );
                my $rule_result = $schema->resultset('voip_header_rules')->create($rule);
                if ($header_actions) {
                    foreach my $action (@$header_actions) {
                        $action->{rule_id} = $rule_result->id;
                        last unless $self->validate_form(
                            c => $c,
                            resource => $action,
                            form => (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ActionAPI", $c)),
                        );
                        last unless NGCP::Panel::Role::API::HeaderRuleActions->check_resource($c, undef, undef, $action, undef, undef);
                        my $action_result = $schema->resultset('voip_header_rule_actions')->create($action);
                    }
                }
                if ($header_conditions) {
                    foreach my $condition (@$header_conditions) {
                        $condition->{rule_id} = $rule_result->id;
                        last unless $self->validate_form(
                            c => $c,
                            resource => $condition,
                            form => (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ConditionAPI", $c)),
                        );
                        last unless NGCP::Panel::Role::API::HeaderRuleConditions->check_resource($c, undef, undef, $condition, undef, undef);
                        my $condition_result = $schema->resultset('voip_header_rule_conditions')->create($condition);
                    }
                }
            }
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $item->id
            );
        }
    } catch($e) {
        $c->log->error("failed to create a header rule set: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create a header rule set.");
        return;
    }

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
