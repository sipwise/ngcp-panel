package NGCP::Panel::Form::Customer::PbxSubscriber;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

use NGCP::Panel::Field::PbxGroup;
with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

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

has_field 'display_name' => (
    type => 'Text',
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The human-readable display name (e.g. John Doe)'] 
    },
    required => 0,
    label => 'Display Name',
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
        title => ['The username to log into the CSC Panel'] 
    },
);

has_field 'webpassword' => (
    type => 'Text',
    label => 'Web Password',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The password to log into the CSC Panel'] 
    },
);

has_field 'username' => (
    type => 'Text',
    label => 'SIP Username',
    required => 1,
    noupdate => 1,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The SIP username for the User-Agents'] 
    },
);

has_field 'password' => (
    type => 'Text',
    label => 'SIP Password',
    required => 1,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['The SIP password for the User-Agents'] 
    },
);

has_field 'status' => (
    type => '+NGCP::Panel::Field::SubscriberStatusSelect',
    label => 'Status',
    validate_when_empty => 1,
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
    #render_list => [qw/display_name webusername webpassword username password status external_id profile_set profile/ ],
    render_list => [qw/e164 display_name email webusername webpassword username password status profile_set profile/ ],
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

    print "++++++++++++++++++++++++++++++++++++++++ PbxSubscriber field_list\n";

    my $profile_set = $self->field('profile_set');
    if($profile_set) {
        $profile_set->field('id')->ajax_src(
            $c->uri_for_action('/subscriberprofile/set_ajax_reseller', [$c->stash->{contract}->contact->reseller_id])->as_string
        );
    }

}

1;

=head1 NAME

NGCP::Panel::Form::Subscriber

=head1 DESCRIPTION

Form to modify a subscriber.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
