package NGCP::Panel::Field::SubscriberLockSelect;
use Moose;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    return [ 
        { label => 'none', value => undef },
        { label => 'foreign', value => 1 },
        { label => 'outgoing', value => 2 },
        { label => 'all calls', value => 3 },
        { label => 'global', value => 4 },
    ];
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
