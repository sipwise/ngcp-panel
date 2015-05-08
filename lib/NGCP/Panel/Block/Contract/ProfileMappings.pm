package NGCP::Panel::Block::Contract::ProfileMappings;

use base ("NGCP::Panel::Block::Block");

sub template {
    my $self = shift;
    return 'contract/profile_mappings_list.tt';
}

1;