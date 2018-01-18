package NGCP::Panel::Controller::API::RewriteRuleSets;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::RewriteRuleSets/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Rewrite;

__PACKAGE__->set_config({
    own_transaction_control => { POST => 1 },
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a collection of <a href="#rewriterules">Rewrite Rules</a>.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for rewriterulesets belonging to a specific reseller',
            query_type => 'string_eq',
        },
        {
            param => 'description',
            description => 'Filter rulesets for a certain description (wildcards possible).',
            query_type => 'string_like',
         },
        {
            param => 'name',
            description => 'Filter rulesets for a certain name (wildcards possible).',
            query_type => 'string_like',
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');
    my $item;
    my $guard = $schema->txn_scope_guard;
    {
        my $rewriterules = delete $resource->{rewriterules};
        try {
            $item = $schema->resultset('voip_rewrite_rule_sets')->create($resource);
        } catch($e) {
            $c->log->error("failed to create rewriteruleset: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create rewriteruleset.");
            return;
        }
        if ($rewriterules) {
            $self->update_rewriterules( $c, $item, $form, $rewriterules );
        }
        $guard->commit;
        NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);
    }
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
