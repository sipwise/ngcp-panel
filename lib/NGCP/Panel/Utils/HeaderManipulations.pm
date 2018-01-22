package NGCP::Panel::Utils::HeaderManipulations;

use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::DateTime;

sub create_condition {
    my %params = @_;
    my ($c, $resource) = @params{qw/c resource/};

    my $schema = $c->model('DB');

    my $values = delete $resource->{values} // [];
    my $item = $schema->resultset('voip_header_rule_conditions')
                    ->create($resource);

    my $group = $schema->resultset('voip_header_rule_condition_value_groups')
                    ->create({ condition_id => $item->id });

    map { $_->{group_id} = $group->id } @{$values};
    $schema->resultset('voip_header_rule_condition_values')
        ->populate($values);

    $item->update({ value_group_id => $group->id });
    $resource->{values} = $values;
    $item->discard_changes();

    return $item;
}

sub update_condition {
    my %params = @_;
    my ($c, $item, $resource) = @params{qw/c item resource/};

    my $schema = $c->model('DB');

    my $values = delete $resource->{values} // [];
    $item->update($resource);
    map { $_->{group_id} = $item->value_group_id } @{$values};
    $item->values->delete;
    $schema->resultset('voip_header_rule_condition_values')
        ->populate($values);
    $resource->{values} = $values;
    $item->discard_changes()
}

1;
