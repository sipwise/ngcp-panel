package NGCP::Panel::Form::SubscriberCFTAdvanced;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::SubscriberCFAdvanced';

has_field 'ringtimeout' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    label => 'after ring timeout',
    element_attr => {
        rel => ['tooltip'],
        title => ['Seconds to wait for pick-up until engaging Call Forward (e.g. &ldquo;10&rdquo;)']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(submitid active_callforward callforward_controls_add ringtimeout)],
);


sub validate_ringtimeout {
    my ($self, $field) = @_;

    if($field->value < 1) {
        my $err_msg = 'Ring Timeout must be greater than 0';
        $field->add_error($err_msg);
    }
}

1;

