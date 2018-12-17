package NGCP::Panel::Controller::API::HeaderRules;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::HeaderRules/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub allowed_methods{
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
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item;
    my $schema = $c->model('DB');
    try {
        $item = $schema->resultset('voip_header_rules')->create($resource);
    } catch($e) {
        $c->log->error("failed to create a header rule: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create a header rule.");
        return;
    }

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
