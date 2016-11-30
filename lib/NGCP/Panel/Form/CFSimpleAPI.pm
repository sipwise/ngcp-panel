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
    type => 'Compound',
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
    type => 'Compound',
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
    type => 'Compound',
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
    type => 'Compound',
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
    type => 'Compound',
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

has_field 'cfu.destinations.announcement_id' => (
    type => 'PosInteger',
);

has_field 'cfu.times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfu.sources' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfu.sources.source' => (
    type => 'Text',
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

has_field 'cfb.destinations.announcement_id' => (
    type => 'PosInteger',
);

has_field 'cfb.times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.sources' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.sources.source' => (
    type => 'Text',
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

has_field 'cft.destinations.announcement_id' => (
    type => 'PosInteger',
);

has_field 'cft.sources' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.sources.source' => (
    type => 'Text',
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

has_field 'cfna.destinations.announcement_id' => (
    type => 'PosInteger',
);

has_field 'cfna.times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.sources' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.sources.source' => (
    type => 'Text',
);

has_field 'cfs.destinations' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.destinations.destination' => (
    type => 'Text',
);

has_field 'cfs.destinations.timeout' => (
    type => 'PosInteger',
);

has_field 'cfs.destinations.announcement_id' => (
    type => 'PosInteger',
);

has_field 'cfs.times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.sources' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.sources.source' => (
    type => 'Text',
);

has_field 'cft.ringtimeout' => (
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
