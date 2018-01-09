package NGCP::Panel::Block::Contract::ProfileMappingsTimeline;

use warnings;
use strict;

use parent ("NGCP::Panel::Block::Block");

sub template {
    my $self = shift;
    return 'contract/profile_mappings_timeline.tt';
}

1;
