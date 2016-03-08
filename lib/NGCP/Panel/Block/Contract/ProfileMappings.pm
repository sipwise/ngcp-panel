package NGCP::Panel::Block::Contract::ProfileMappings;

use parent ("NGCP::Panel::Block::Block");

sub template {
    my $self = shift;
    return 'contract/profile_mappings_list.tt';
}

1;