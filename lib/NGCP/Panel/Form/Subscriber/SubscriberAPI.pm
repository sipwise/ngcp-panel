package NGCP::Panel::Form::Subscriber::SubscriberAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Subscriber';

sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'display_name' => (
    type => 'Text',
    label => 'Display Name',
    element_attr => {
        rel => ['tooltip'],
        title => ['The person\'s name, which is then used in XMPP contact lists or auto-provisioned phones, and which can be used as network-provided display name in SIP calls.']
    },
);

has_field 'alias_numbers' => (
    type => '+NGCP::Panel::Field::AliasNumber',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Additional E.164 numbers mapped to this subscriber for inbound calls.']
    },
);

has_field 'lock' => (
    type => '+NGCP::Panel::Field::SubscriberLockSelect',
    label => 'Lock Level',
    element_attr => {
        rel => ['tooltip'],
        title => ['The lock level of the subscriber.']
    },
);

has_field 'is_pbx_group' => (
    type => 'Boolean',
    label => 'Is PBX Group?',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether this subscriber is used as PBX group.']
    },
);

has_field 'pbx_group' => (
    type => '+NGCP::Panel::Field::SubscriberPbxGroup',
    label => 'PBX Group',
    element_attr => {
        rel => ['tooltip'],
        title => ['The PBX group id this subscriber belongs to.']
    },
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);


has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contract domain e164 alias_number webusername webpassword username password status lock external_id administrative is_pbx_group pbx_group display_name/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
