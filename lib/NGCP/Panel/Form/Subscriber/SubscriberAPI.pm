package NGCP::Panel::Form::Subscriber::SubscriberAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Subscriber';

sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'customer' => (
    type => '+NGCP::Panel::Field::CustomerContract',
    label => 'Customer',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract used for this subscriber.']
    },
);

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
        title => ['Additional E.164 numbers (each containing a cc, ac and sn attribute) mapped to this subscriber for inbound calls.'],
    },
);

has_field 'lock' => (
    type => '+NGCP::Panel::Field::SubscriberLockSelect',
    label => 'Lock Level',
    element_attr => {
        rel => ['tooltip'],
        title => ['The lock level of the subscriber.'],
    },
);

has_field 'is_pbx_pilot' => (
    type => 'Boolean',
    label => 'Is PBX Pilot?',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether this subscriber is used as PBX pilot subscriber.'],
    },
);

has_field 'pbx_extension' => (
    type => 'Text',
    label => 'PBX Extension',
    element_attr => {
        rel => ['tooltip'],
        title => ['The PBX extension used for short dialling. If provided, the primary number will automatically be derived from the pilot subscriber\'s primary number suffixed by this extension.']
    },
);


has_field 'is_pbx_group' => (
    type => 'Boolean',
    label => 'Is PBX Group?',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether this subscriber is used as PBX group.'],
    },
);

has_field 'pbx_group_ids' => (
    type => '+NGCP::Panel::Field::PbxGroupAPI',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of PBX group ids this subscriber belongs to.'],
    },
);

has_field 'pbx_hunt_policy' => (
    type => 'Select',
    options => [
        { value => 'serial', label => 'serial'},
        { value => 'parallel', label => 'parallel'},
        { value => 'random', label => 'random'},
        { value => 'circular', label => 'circular'},
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ["Hunting policy, one of serial, parallel, random, circular."],
    },
);

has_field 'pbx_hunt_timeout' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['Hunting Timeout'],
    },
);
has_field 'cloud_pbx_hunt_policy' => (
    type => 'Select',
    options => [
        { value => 'serial', label => 'serial'},
        { value => 'parallel', label => 'parallel'},
        { value => 'random', label => 'random'},
        { value => 'circular', label => 'circular'},
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ["Hunting policy, one of serial, parallel, random, circular."],
    },
);

has_field 'cloud_pbx_hunt_timeout' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['Hunting Timeout'],
    },
);

has_field 'profile' => (
    type => '+NGCP::Panel::Field::SubscriberProfile',
    label => 'Subscriber Profile',
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile defining the actual feature set for this subscriber.'],
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
    render_list => [qw/customer domain pbx_extension e164 alias_numbers email webusername webpassword username password status lock external_id administrative is_pbx_group pbx_group_ids is_pbx_pilot display_name profile_set profile/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

# override parent here to prevent any password magic
sub update_fields {
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    # make sure we don't use contract, as we have customer
    $self->field('contract')->inactive(1);

    if($c->config->{security}->{password_sip_autogenerate}) {
        $self->field('password')->required(0);
    }
    if($c->config->{security}->{password_web_autogenerate}) {
        $self->field('webpassword')->required(0);
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
