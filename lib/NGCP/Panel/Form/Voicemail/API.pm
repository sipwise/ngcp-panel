package NGCP::Panel::Form::Voicemail::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'pin' => (
    type => 'Text',
    label => 'PIN',
    minlength => 4,
    maxlength => 31,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The PIN used to enter the IVR menu from external numbers.']
    },
);

has_field 'email' => (
    type => 'Email',
    label => 'Email Address',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email address where to send notifications and the recordings.']
    },
)

has_field 'delete' => (
    type => 'Boolean',
    label => 'Delete Messages',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Delete voicemail recordings from the mailbox after delivering them via email.']
    },
);

has_field 'attach' => (
    type => 'Boolean',
    label => 'Attach Recording',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Attach recordings when delivering them via email. Must be set if delete flag is set']
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
    render_list => [qw/pin email attach delete/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {
    my $self = shift;
    my $attach = $self->field('attach')->value;
    my $delete = $self->field('delete')->value;
    if($delete && !$attach) {
        $self->field('attach')->add_error('Must be set if delete is set');
    }
}


1;
# vim: set tabstop=4 expandtab:
