package NGCP::Panel::Form::SubscriberCFTSimple;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::SubscriberCFSimple';

has_field 'ringtimeout' => (
	type => '+NGCP::Panel::Field::PosInteger', 
	required => 1,
	label => 'after ring timeout',
    element_attr => {
        rel => ['tooltip'],
        title => ['Seconds to wait for pick-up until engaging Call Forward (e.g. &ldquo;10&rdquo;)']
    },
    default => 15,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(destination ringtimeout enabled)],
);

sub validate_ringtimeout {
    my ($self, $field) = @_;

    if($field->value < 1) {
        my $err_msg = 'Ring Timeout must be greater than 0';
        $field->add_error($err_msg);
    }
}

1;
# vim: set tabstop=4 expandtab:
