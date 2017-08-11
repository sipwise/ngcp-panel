package NGCP::Panel::Form::Number::SubadminAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'cc' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Country Code, e.g. 1 for US or 43 for Austria'] 
    },
    required => 1,
);

has_field 'ac' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Area Code, e.g. 212 for NYC or 1 for Vienna'] 
    },
    required => 1,
);

has_field 'sn' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Subscriber Number, e.g. 12345678'] 
    },
    required => 1,
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The id of the subscriber the number is assigned to.']
    },
);

1;
# vim: set tabstop=4 expandtab:
