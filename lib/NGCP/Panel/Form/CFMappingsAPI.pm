package NGCP::Panel::Form::CFMappingsAPI;
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
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unconditional'] 
    },
);

has_field 'cfb' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Busy'] 
    },
);

has_field 'cft' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Timeout'] 
    },
);

has_field 'cfna' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unavailable'] 
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

has_field 'cft_ringtimeout' => (
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
