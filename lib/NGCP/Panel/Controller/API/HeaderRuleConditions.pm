package NGCP::Panel::Controller::API::HeaderRuleConditions;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::HeaderManipulations;
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::HeaderRuleConditions/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
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
        $item = $schema->resultset('voip_header_rule_conditions')
                        ->create($resource);
        NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
            c => $c, set_id => $item->rule->ruleset->id
        );
    } catch($e) {
        $c->log->error("failed to create a header rule condition: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create a header rule condition.");
        return;
    }

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
