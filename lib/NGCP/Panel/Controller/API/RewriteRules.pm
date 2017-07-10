package NGCP::Panel::Controller::API::RewriteRules;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::RewriteRules/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use HTTP::Status qw(:constants);

__PACKAGE__->set_config();

sub _set_config{
    my ($self, $method) = @_;
    return {
        own_transaction_control => {all => 1},
    };
}

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
    $resource->{match_pattern} = $form->values->{match_pattern};
    $resource->{replace_pattern} = $form->values->{replace_pattern};

    my $item;

    unless(defined $resource->{set_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required: 'set_id'");
        return;
    }

    my $reseller_id;
    if($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }

    my $ruleset = $schema->resultset('voip_rewrite_rule_sets')->find({
        id => $resource->{set_id},
        ($reseller_id ? (reseller_id => $reseller_id) : ()),
    });
    unless($ruleset) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'set_id'.");
        return;
    }
    try {
        $item = $schema->resultset('voip_rewrite_rules')->create($resource);
    } catch($e) {
        $c->log->error("failed to create rewriterule: $e"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create rewriterule.");
        return;
    }
    return $item;
}
1;

# vim: set tabstop=4 expandtab:
