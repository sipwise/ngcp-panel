package NGCP::Panel::Form::Subscriber;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

use NGCP::Panel::Field::Domain;
use NGCP::Panel::Field::CustomerContract;
use NGCP::Panel::Field::PosInteger;
use NGCP::Panel::Field::Identifier;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'contract' => (
    type => '+NGCP::Panel::Field::CustomerContract',
    label => 'Customer',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract used for this subscriber.']
    },
);

has_field 'webusername' => (
    type => 'Text',
    label => 'Web Username',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The username to log into the CSC Panel.'] 
    },
);

has_field 'webpassword' => (
    type => 'Text',
    label => 'Web Password',
    required => 0,
    minlength => 6,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The password to log into the CSC Panel.'] 
    },
);

has_field 'e164' => (
    type => '+NGCP::Panel::Field::E164',
    order => 99,
    required => 0,
    label => 'E164 Number',
    do_label => 1,
    do_wrapper => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The main E.164 number (containing a cc, ac and sn attribute) used for inbound and outbound calls.']
    },
);

has_field 'username' => (
    type => '+NGCP::Panel::Field::Identifier',
    label => 'SIP Username',
    required => 1,
    noupdate => 1,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The username for SIP and XMPP services.'] 
    },
);

has_field 'domain' => (
    type => '+NGCP::Panel::Field::Domain',
    label => 'SIP Domain',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The domain name or domain id this subscriber belongs to.']
    },
);

has_field 'password' => (
    type => 'Text',
    label => 'SIP Password',
    required => 1,
    minlength => 6,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The password to authenticate for SIP and XMPP services.'] 
    },
);

has_field 'status' => (
    type => '+NGCP::Panel::Field::SubscriberStatusSelect',
    label => 'Status',
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the subscriber (one of "active", "locked", "terminated").']
    },
);

has_field 'administrative' => (
    type => 'Boolean',
    label => 'Administrative',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Whether the subscriber can configure other subscribers within his Customer account.'] 
    },
);


has_field 'external_id' => (
    type => 'Text',
    label => 'External ID',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['An external id, e.g. provided by a 3rd party provisioning.'] 
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
    render_list => [qw/contract domain e164 webusername webpassword username password status external_id administrative/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
