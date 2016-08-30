package NGCP::Panel::Form::CFSourceSetAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber id this source set belongs to']
    },
);

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    wrapper_class => [qw/hfh-rep-field/],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the source set']
    },
);

has_field 'sources' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of sources, each containing the key "source" ' .
                  'which will be matched against the call\'s anumber to determine ' .
                  'whether to apply the callforward or not.',
        ]
    },
);

has_field 'sources.id' => (
    type => 'Hidden',
);

has_field 'sources.source' => (
    type => 'Text',
    label => 'Source',
);

1;

# vim: set tabstop=4 expandtab:
