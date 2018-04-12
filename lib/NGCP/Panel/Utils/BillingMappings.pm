package NGCP::Panel::Utils::BillingMappings;
use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::DateTime qw();





sub x {

    #foreach my $billing_mapping$contract->billing_mappings->all)




}

sub get_actual_billing_mapping {
    my %params = @_;
    my ($c,$schema,$contract,$now) = @params{qw/c schema contract now/};
    $schema //= $c->model('DB');
    $now //= NGCP::Panel::Utils::DateTime::current_local;
    my $contract_create = NGCP::Panel::Utils::DateTime::set_local_tz($contract->create_timestamp // $contract->modify_timestamp);
    my $dtf = $schema->storage->datetime_parser;
    $now = $contract_create if $now < $contract_create; #if there is no mapping starting with or before $now, it would returns the mapping with max(id):
    return $schema->resultset('billing_mappings_actual')->search({ contract_id => $contract->id },{bind => [ ( $dtf->format_datetime($now) ) x 2, ($contract->id) x 2 ],})->first;
}

1;
