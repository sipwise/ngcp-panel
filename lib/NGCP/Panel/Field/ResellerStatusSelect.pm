package NGCP::Panel::Field::ResellerStatusSelect;
use Moose;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    return [ 
        { label => 'Select...', value => '' },
        { label => 'active', value => 'active' },
        { label => 'locked', value => 'locked' },
        { label => 'terminated', value => 'terminated' },
    ];
}

1;

# vim: set tabstop=4 expandtab:
