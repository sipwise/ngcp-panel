package NGCP::Panel::Field::Contract;
use Moose;
extends 'HTML::FormHandler::Field::Select';

use Data::Dumper;

sub build_options {
    my ($self) = @_;

    return [ 
        { label => 'Select...', value => '' },
        { label => '1', value => 1 },
        { label => '2', value => 2 },
        { label => '3', value => 3 },
        { label => '4', value => 4 },
        { label => '5', value => 5 },
        { label => '6', value => 6 },
    ];
}

1;

# vim: set tabstop=4 expandtab:
