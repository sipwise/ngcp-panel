package NGCP::Panel::Form::LoginOtp;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::Password qw();

has '+widget_wrapper' => ( default => 'Bootstrap' );

sub build_render_list {
    my $self = shift;
    my @list = qw(username password);
    push(@list,'otp_registration_info') if $self->{ctx}->stash->{'show_otp_registration_info'};
    push(@list,"otp","submit");
    return \@list;
}
sub build_form_tags {{ error_class => 'label label-secondary'}}

has_field 'username' => (
    type => 'Text',
    required => 1,
    element_attr => { readonly => 1, placeholder => 'Username' },
    element_class => [qw/login username-field/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'password' => (
    type => '+NGCP::Panel::Field::Password',
    required => 1,
    element_attr => { readonly => 1, placeholder => 'Password' },
    element_class => [qw/login password-field/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_block 'otp_registration_info' => (
    type => '+NGCP::Panel::Block::Login::OtpRegistrationInfo',
);

has_field 'otp' => (
    type => 'Text',
    required => 1,
    element_attr => { placeholder => 'One-Time Code' },
    element_class => [qw/login otp-field/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'submit' => (
    type => 'Submit',
    value => 'Sign In',
    label => '',
    element_class => [qw/button btn btn-primary btn-large/],
);

1;

