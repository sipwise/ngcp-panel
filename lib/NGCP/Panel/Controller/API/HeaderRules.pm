package NGCP::Panel::Controller::API::HeaderRules;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::HeaderManipulations;
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::HeaderRules/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub allowed_methods {
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a set of Header Manipulation Rules.';
};

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for header rules with a specific name (wildcard pattern allowed)',
            query_type => 'string_like',
        },
        {
            param => 'description',
            description => 'Filter rules for a certain description (wildcards possible).',
            query_type  => 'string_like',
        },
        {
            param => 'set_id',
            description => 'Filter for rules belonging to a specific header rule set.',
            query_type  => 'string_eq',
        },
        {
            param => 'subscriber_id',
            description => 'Filter for header rule sets of a specific subscriber',
        }
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item;
    my $schema = $c->model('DB');
    try {
        my $header_actions = delete $resource->{actions};
        my $header_conditions = delete $resource->{conditions};
        $item = $schema->resultset('voip_header_rules')->create($resource);
        if ($header_actions) {
            foreach my $action (@$header_actions) {
                $action->{rule_id} = $item->id;
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
                $condition->{rule_id} = $item->id;
                last unless $self->validate_form(
                    c => $c,
                    resource => $condition,
                    form => (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ConditionAPI", $c)),
                );
                last unless NGCP::Panel::Role::API::HeaderRuleConditions->check_resource($c, undef, undef, $condition, undef, undef);
                my $condition_result = $schema->resultset('voip_header_rule_conditions')->create($condition);
            }
        }
        NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
            c => $c, set_id => $item->ruleset->id
        );
    } catch($e) {
        $c->log->error("failed to create a header rule: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create a header rule.");
        return;
    }

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
