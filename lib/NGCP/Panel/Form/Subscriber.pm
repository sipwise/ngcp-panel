package NGCP::Panel::Form::Subscriber;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

use NGCP::Panel::Field::Domain;
use NGCP::Panel::Field::CustomerContract;
use NGCP::Panel::Field::PosInteger;
use NGCP::Panel::Field::Identifier;
use NGCP::Panel::Utils::Form;

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

has_field 'profile_set' => (
    type => '+NGCP::Panel::Field::SubscriberProfileSet',
    label => 'Subscriber Profile',
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile set defining the possible feature sets for this subscriber.']
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
    render_list => [qw/contract domain e164 email webusername webpassword username password status external_id administrative profile_set/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
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
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    if($c->config->{security}->{password_sip_autogenerate} && $self->field('password')) {
        $self->field('password')->inactive(1);
        $self->field('password')->required(0);
    }
    if($c->config->{security}->{password_web_autogenerate} && $self->field('webpassword')) {
        $self->field('webpassword')->inactive(1);
        $self->field('webpassword')->required(0);
    }

=pod
# we don't have a contract here, so we can't filter on it yet
# (would only be possible via javascript, no framework for that yet)
    if($self->field('profile_set')) {
        $self->field('profile_set')->field('id')->ajax_src(
            $c->uri_for_action('/subscriberprofile/set_ajax_reseller', [$c->stash->{contract}->contact->reseller_id])->as_string
        );
    }
=cut

}

1;

# vim: set tabstop=4 expandtab:
