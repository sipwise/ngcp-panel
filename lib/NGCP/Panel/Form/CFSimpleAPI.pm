package NGCP::Panel::Form::CFSimpleAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden',
    noupdate => 1,
);

has_field 'cfu' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unconditional, Contains the keys "destinations" and "times". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always.'],
    },
);

has_field 'cfb' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Busy, Contains the keys "destinations" and "times". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always.'],
    },
);

has_field 'cft' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Timeout, Contains the keys "destinations" and "times". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always.'],
    },
);

has_field 'cfna' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unavailable, Contains the keys "destinations" and "times". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always.'],
    },
);

has_field 'cfu.destinations' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfu.destinations.destination' => (
    type => 'Text',
);

has_field 'cfu.destinations.timeout' => (
    type => 'PosInteger',
);

has_field 'cfu.times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.destinations' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.destinations.destination' => (
    type => 'Text',
);

has_field 'cfb.destinations.timeout' => (
    type => 'PosInteger',
);

has_field 'cfb.times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.destinations' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.destinations.destination' => (
    type => 'Text',
);

has_field 'cft.destinations.timeout' => (
    type => 'PosInteger',
);

has_field 'cft.times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.destinations' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.destinations.destination' => (
    type => 'Text',
);

has_field 'cfna.destinations.timeout' => (
    type => 'PosInteger',
);

has_field 'cfna.times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.ringtimeout' => (
    type => 'PosInteger',
    do_wrapper => 1,
    do_label => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(cfu cfb cft cfna)],
);

1;

# vim: set tabstop=4 expandtab:
