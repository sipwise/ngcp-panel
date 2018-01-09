package NGCP::Panel::Block::Contract::ProfileNetworkMappings;

use warnings;
use strict;

use parent ("NGCP::Panel::Block::Block");

sub template {
    my $self = shift;
    return 'contract/profile_network_mappings_list.tt';
}

1;