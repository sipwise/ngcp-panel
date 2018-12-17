package NGCP::Panel::Controller::API::HeaderRuleConditions;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::HeaderRuleConditions/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a set of Header Manipulation Rule Conditions.';
};

sub query_params {
    return [
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item;
    my $schema = $c->model('DB');
    my $guard = $schema->txn_scope_guard;
    {
        try {
            my $values = delete $resource->{values} // [];
            $item = $schema->resultset('voip_header_rule_conditions')
                            ->create($resource);

            my $group = $schema->resultset('voip_header_rule_condition_value_groups')
                            ->create({ condition_id => $item->id });

            map { $_->{group_id} = $group->id } @{$values};
            $schema->resultset('voip_header_rule_condition_values')
                ->populate($values);

            $item->update({ value_group_id => $group->id });
            $resource->{values} = $values;
            $item->discard_changes();
        } catch($e) {
            $c->log->debug("WTF: $e");
            $c->log->error("failed to create a header rule condition: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create a header rule condition.");
            return;
        }
        $guard->commit;
    }

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
