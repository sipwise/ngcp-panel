package NGCP::Panel::Form::SubscriberCFTSimple;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'NGCP::Panel::Form::SubscriberCFSimple';

has_field 'ringtimeout' => (
	type => 'PosInteger', 
	required => 1,
	label => 'after ring timeout',
);
has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(destination ringtimeout)],
);

1;
