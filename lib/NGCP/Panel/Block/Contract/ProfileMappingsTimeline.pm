package NGCP::Panel::Block::Contract::ProfileMappingsTimeline;

use parent ("NGCP::Panel::Block::Block");

sub template {
    my $self = shift;
    return 'contract/profile_mappings_timeline.tt';
}

1;
