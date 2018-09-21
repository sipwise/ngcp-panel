package NGCP::Panel::Form::Subscriber::SubscriberSubAdminAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use NGCP::Panel::Utils::Form qw();

#e164 administrative timezone profile_set are absent in web ui

has_field 'contract' => (
    type => '+NGCP::Panel::Field::CustomerContract',
    label => 'Customer',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract used for this subscriber.']
    },
);

has_field 'email' => (
    type => 'Email',
    required => 0,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email address of the subscriber.']
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
    element_attr => {
        rel => ['tooltip'],
        title => ['The username for SIP and XMPP services.']
    },
);

has_field 'domain' => (
    #fields will be or will be not renamed to the name_id for the API documentation, Anyway, it will be not duplicated, so "or name or id" is not correct
    type => '+NGCP::Panel::Field::Domain',
    label => 'SIP Domain',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The domain id this subscriber belongs to.'],
        implicit_parameter => {
            type => "String",
            required => 0,
            validate_when_empty => 0,
            element_attr => {
                title => ['The domain name this subscriber belongs to.'],
            },
        },
    },
);

has_field 'password' => (
    type => 'Text',
    label => 'SIP Password',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The password to authenticate for SIP and XMPP services.']
    },
);



has_field 'administrative' => (
    type => 'Boolean',
    label => 'Administrative',
    required => 0,
    readonly => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether the subscriber can configure other subscribers within his Customer account.']
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

has_field 'timezone' => (
    type => '+NGCP::Panel::Field::TimezoneSelect',
    label => 'Timezone',
    element_attr => {
        rel => ['tooltip'],
        title => ['The timezone of the subscriber.']
    },
);
#we need customer_id field in the form to don't delete customer_id from the resource as absent field during form validation
#but for subscriberadmin role value always will be pilot->account_id
#for subscriber we have read-only access
#but we use resource->{customer_id} to get customer in prepare resource
has_field 'customer_id' => (
    type => 'PosInteger',
    label => 'Customer',
    validate_when_empty => 1,
    required => 1,
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
    maxlength => 128,
);

has_field 'alias_numbers' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Additional E.164 numbers (each containing a cc, ac and sn attribute) mapped to this subscriber for inbound calls.'],
    },
);

has_field 'alias_numbers.contains' => (
    type => '+NGCP::Panel::Field::E164',
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

has_field 'pbx_groupmember_ids' => (
    type => '+NGCP::Panel::Field::PbxGroupMemberAPI',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of PBX subscriber ids belonging to this group.'],
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



sub validate_password {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    NGCP::Panel::Utils::Form::validate_password(c => $c, field => $field);
}

sub validate_webpassword {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    NGCP::Panel::Utils::Form::validate_password(c => $c, field => $field);
}

sub update_fields {
#IMPORTANT! redefined sub update_fields with no super call disable call of the update_field_list and defaults methods
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    # make sure we don't use contract, as we have customer
    $self->field('contract')->inactive(1);

    if($c->config->{security}->{password_sip_autogenerate} && $self->field('password')) {
        $self->field('password')->inactive(1);
        $self->field('password')->required(0);
    }
    if($c->config->{security}->{password_web_autogenerate} && $self->field('webpassword')) {
        $self->field('webpassword')->inactive(1);
        $self->field('webpassword')->required(0);
    }
}

1;

# vim: set tabstop=4 expandtab:
