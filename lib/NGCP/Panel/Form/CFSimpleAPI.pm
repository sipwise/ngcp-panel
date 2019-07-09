package NGCP::Panel::Form::CFSimpleAPI;
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
    type => '+NGCP::Panel::Field::CFSimpleAPICompound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unconditional, Contains the keys "destinations", "times" and "sources". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always. ' .
                  '"sources" is an Array of Objects having one field "source". "sources" can be empty.'],
    },
);

has_field 'cfb' => (
    type => '+NGCP::Panel::Field::CFSimpleAPICompound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Busy, Contains the keys "destinations", "times" and "sources". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always. ' .
                  '"sources" is an Array of Objects having one field "source". "sources" can be empty.'],
    },
);

has_field 'cft' => (
    type => '+NGCP::Panel::Field::CFSimpleAPICompound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Timeout, Contains the keys "destinations", "times", "sources" and "ringtimeout". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always. ' .
                  '"sources" is an Array of Objects having one field "source". "sources" can be empty.' .
                  '"ringtimeout" is a numeric ringing time value in seconds before call forward will be applied.'],
    },
);

has_field 'cfna' => (
    type => '+NGCP::Panel::Field::CFSimpleAPICompound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unavailable, Contains the keys "destinations", "times" and "sources". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always. ' .
                  '"sources" is an Array of Objects having one field "source". "sources" can be empty.'],
    },
);

has_field 'cfs' => (
    type => '+NGCP::Panel::Field::CFSimpleAPICompound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward SMS, Contains the keys "destinations", "times" and "sources". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always. ' .
                  '"sources" is an Array of Objects having one field "source". "sources" can be empty.'],
    },
);

has_field 'cfr' => (
    type => '+NGCP::Panel::Field::CFSimpleAPICompound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Call Forward on Response, Contains the keys "destinations", "times" and "sources". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always. ' .
                  '"sources" is an Array of Objects having one field "source". "sources" can be empty.'],
    },
);

has_field 'cfo' => (
    type => '+NGCP::Panel::Field::CFSimpleAPICompound',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Call Forward on Overflow, Contains the keys "destinations", "times" and "sources". "destinations" is an Array of Objects ' .
                  'having a "destination", "priority" and "timeout" field. "times" is an Array of Objects having the fields ' .
                  '"minute", "hour", "wday", "mday", "month", "year". "times" can be empty, then the CF is applied always. ' .
                  '"sources" is an Array of Objects having one field "source". "sources" can be empty.'],
    },
);

has_field 'cft.ringtimeout' => (
    type => 'PosInteger',
    do_wrapper => 1,
    do_label => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(cfu cfb cft cfna cfs cfr cfo)],
);

1;

# vim: set tabstop=4 expandtab:
