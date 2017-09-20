package NGCP::Panel::Form::Capabilities::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'PosInteger',
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The id of the capability.'] 
    },
);


has_field 'name' => (
    type => 'Text',
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The name of the capability.'] 
    },
);

has_field 'enabled' => (
    type => 'Boolean',
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Whether the capability is enabled.'] 
    },
);

1;
# vim: set tabstop=4 expandtab:
