package NGCP::Panel::Controller::API::RewriteRules;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::RewriteRules/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    own_transaction_control => { POST => 1 },
});


sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a set of Rewrite Rules which are grouped in <a href="#rewriterulesets">Rewrite Rule Sets</a>. They can be used to alter incoming and outgoing numbers.';
};

sub query_params {
    return [
        {
            param => 'description',
            description => 'Filter rules for a certain description (wildcards possible).',
            query_type  => 'string_like',
        },
        {
            param => 'set_id',
            description => 'Filter for rules belonging to a specific rewriteruleset.',
            query_type  => 'string_eq',
        },
        {
            param => 'reseller_id',
            description => 'Filter for rules belonging to a specific reseller.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'ruleset.reseller_id' => $q };
                },
                second => sub { join => 'ruleset' },
            },
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');
    my $guard = $schema->txn_scope_guard;

    my $item;

    try {
        $item = $schema->resultset('voip_rewrite_rules')->create($resource);
    } catch($e) {
        $c->log->error("failed to create rewriterule: $e"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create rewriterule.");
        return;
    }
    $guard->commit;
    NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);
    
    return $item;
}
1;

# vim: set tabstop=4 expandtab:
