package NGCP::Panel::Controller::API::HeaderRuleConditions;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::HeaderManipulations;
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::HeaderRuleConditions/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    allowed_ngcp_types => [qw/carrier sppro/],
    required_licenses => [qw/header_manipulation/],
});

sub allowed_methods {
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a set of Header Manipulation Rule Conditions.';
};

sub query_params {
    return [
        {
            param => 'set_id',
            description => 'Filter for header rule conditions of a specific header rule set',
            query_type => 'string_eq',
        },
        {
            param => 'rule_id',
            description => 'Filter for header rule conditions of a specific header rule',
            query_type => 'string_eq',
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item;
    my $schema = $c->model('DB');
    try {
        $self->pre_process_form_resource($c, undef, undef, $resource, $form, $process_extras);
        $item = $schema->resultset('voip_header_rule_conditions')
                        ->create($resource);
        NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
            c => $c, set_id => $item->rule->ruleset->id
        );
    } catch($e) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create a header rule condition.", $e);
        return;
    }

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
