package NGCP::Panel::Block::Contract::BillingMappings;

use base ("NGCP::Panel::Block::Block");

sub template {
    my $self = shift;
    return 'contract/billing_mappings_list.tt';
}

1;