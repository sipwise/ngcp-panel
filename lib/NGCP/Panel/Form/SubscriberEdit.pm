package NGCP::Panel::Form::SubscriberEdit;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

use NGCP::Panel::Field::Domain;
use NGCP::Panel::Field::CustomerContract;
use NGCP::Panel::Field::Reseller;
use NGCP::Panel::Field::PosInteger;
use NGCP::Panel::Utils::Form;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

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
        title => ['The username to log into the CSC Panel'] 
    },
);

has_field 'webpassword' => (
    type => 'Text',
    label => 'Web Password',
    required => 0,
    minlength => 6,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The password to log into the CSC Panel'] 
    },
);

has_field 'e164' => (
    type => '+NGCP::Panel::Field::E164',
    order => 99,
    required => 0,
    label => 'E164 Number',
    do_label => 1,
    do_wrapper => 1,
);


has_field 'alias_number' => (
    type => '+NGCP::Panel::Field::AliasNumber',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'alias_number_add' => (
    type => 'AddElement',
    repeatable => 'alias_number',
    value => 'Add another number',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'password' => (
    type => 'Text',
    label => 'SIP Password',
    required => 0, # optional on edit
    minlength => 6,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The SIP password for the User-Agents'] 
    },
);

has_field 'lock' => (
    type => '+NGCP::Panel::Field::SubscriberLockSelect',
    label => 'Lock Level',
    validate_when_empty => 1,
);

has_field 'status' => (
    type => '+NGCP::Panel::Field::SubscriberStatusSelect',
    label => 'Status',
    validate_when_empty => 1,
);

has_field 'administrative' => (
    type => 'Boolean',
    label => 'Administrative',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Subscriber can configure other subscribers within the Customer Account'] 
    },
);


has_field 'external_id' => (
    type => 'Text',
    label => 'External ID',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['An external id, e.g. provided by a 3rd party provisioning'] 
    },
);

has_field 'profile_set' => (
    type => '+NGCP::Panel::Field::SubscriberProfileSet',
    label => 'Subscriber Profile Set',
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile set defining the possible feature sets for this subscriber.']
    },
);

has_field 'profile' => (
    type => '+NGCP::Panel::Field::SubscriberProfile',
    label => 'Subscriber Profile',
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile defining the actual feature set for this subscriber.']
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
    render_list => [qw/e164 alias_number alias_number_add email webusername webpassword password lock status external_id administrative profile_set profile/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub field_list {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless($c);

    my $profile_set = $self->field('profile_set');
    $profile_set->field('id')->ajax_src(
        $c->uri_for_action('/subscriberprofile/set_ajax_reseller', [$c->stash->{subscriber}->contract->contact->reseller_id])->as_string
    );

    my $set_id = $c->stash->{subscriber}->provisioning_voip_subscriber->profile_set_id;
    if($set_id) {
        my $profile = $self->field('profile');
        $profile->field('id')->ajax_src(
            $c->uri_for_action('/subscriberprofile/profile_ajax', [$set_id])->as_string
        );
    }
}

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

1;

# vim: set tabstop=4 expandtab:
