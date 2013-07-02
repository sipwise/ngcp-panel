package NGCP::Panel::Field::ContractStatusSelect;
use Moose;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    return [ 
        { label => 'active', value => 'active' },
        { label => 'pending', value => 'pending' },
        { label => 'locked', value => 'locked' },
        { label => 'terminated', value => 'terminated' },
    ];
}

1;

# vim: set tabstop=4 expandtab:
