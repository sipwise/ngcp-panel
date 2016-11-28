package NGCP::Panel::Form::Voicemail::Pager;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'sms_number' => (
    type => 'Text',
    label => 'SMS Number',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The E164 number in format <cc><ac><sn> to send voicemail notification SMS.']
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
    render_list => [qw/sms_number/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_sms_number {
    my ($self, $field) = @_;

    unless($field->value =~ /^[1-9]\d+$/) {
        my $err_msg = 'Invalid E164 number';
        $field->add_error($err_msg);
    }
}

1;
# vim: set tabstop=4 expandtab:
