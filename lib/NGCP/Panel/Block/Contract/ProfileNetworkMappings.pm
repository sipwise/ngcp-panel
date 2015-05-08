package NGCP::Panel::Block::Contract::ProfileNetworkMappings;

use base ("NGCP::Panel::Block::Block");

sub template {
    my $self = shift;
    return 'contract/profile_network_mappings_list.tt';
}

1;