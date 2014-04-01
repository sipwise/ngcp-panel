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
    required => 1,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unconditional'] 
    },
);

has_field 'cfb' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
    required => 1,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Busy'] 
    },
);

has_field 'cft' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
    required => 1,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Timeout'] 
    },
);

has_field 'cfna' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
    required => 1,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unavailable'] 
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
    type => 'Text',
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
    type => 'Text',
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
    type => 'Text',
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
    type => 'Text',
);

has_field 'cfna.times' => (
    type => 'Repeatable',
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
