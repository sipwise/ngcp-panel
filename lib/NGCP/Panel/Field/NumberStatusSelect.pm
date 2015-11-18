package NGCP::Panel::Field::NumberStatusSelect;
use Moose;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    return [ 
        { label => 'active', value => 'active' },
        { label => 'reserved', value => 'reserved' },
        { label => 'locked', value => 'locked' },
        { label => 'deported', value => 'deported' },
    ];
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
