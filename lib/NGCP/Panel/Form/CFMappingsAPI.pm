package NGCP::Panel::Form::CFMappingsAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden',
    noupdate => 1,
);

has_field 'cfu' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unconditional, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cfb' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Busy, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cft' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Timeout, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cfna' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unavailable, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cfs' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward SMS, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cfu.destinationset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfu.timeset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfu.sourceset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.destinationset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.timeset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.sourceset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.destinationset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.timeset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.sourceset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.destinationset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.timeset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.sourceset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.destinationset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.timeset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.sourceset' => (
    type => 'Text',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft_ringtimeout' => (
    type => 'PosInteger',
    do_wrapper => 1,
    do_label => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(cfu cfb cft cfna cfs)],
);

1;

# vim: set tabstop=4 expandtab:
