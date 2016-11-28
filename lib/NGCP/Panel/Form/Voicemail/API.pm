package NGCP::Panel::Form::Voicemail::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );

has_field 'pin' => (
    type => 'Text',
    minlength => 4,
    maxlength => 31,
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The PIN used to enter the IVR menu from external numbers.']
    },
);

has_field 'email' => (
    type => 'Email',
    required => 0,
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email address where to send notifications and the recordings.']
    },
);

has_field 'delete' => (
    type => 'Boolean',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Delete voicemail recordings from the mailbox after delivering them via email.']
    },
);

has_field 'attach' => (
    type => 'Boolean',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Attach recordings when delivering them via email. Must be set if delete flag is set']
    },
);

has_field 'sms_number' => (
    type => 'Text',
    required => 0,
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The E164 number in format &lt;cc&gt;&lt;ac&gt;&lt;sn&gt; to send voicemail notification SMS.']
    },
);


sub validate {
    my $self = shift;
    my $attach = $self->field('attach')->value;
    my $delete = $self->field('delete')->value;
    if($delete && !$attach) {
        $self->field('attach')->add_error('Must be set if delete is set');
    }
}

sub validate_sms_number {
    my ($self, $field) = @_;

    unless($field->value =~ /^[1-9]\d+$/) {
        my $err_msg = 'Invalid E164 number';
        $field->add_error($err_msg);
    }
}


1;
# vim: set tabstop=4 expandtab:
