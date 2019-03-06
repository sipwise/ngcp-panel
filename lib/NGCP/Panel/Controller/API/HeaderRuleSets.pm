package NGCP::Panel::Controller::API::HeaderRuleSets;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::HeaderRuleSets/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
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
        $item = $schema->resultset('voip_header_rule_sets')->create($resource);
    } catch($e) {
        $c->log->error("failed to create a header rule set: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create a header rule set.");
        return;
    }

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
