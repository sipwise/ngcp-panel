package NGCP::Panel::Form::Subscriber::WebfaxAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Subscriber::Webfax';
#use Moose::Util::TypeConstraints;

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber the fax belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/subscriber_id destination resolution coverpage data faxfile/],
);

1;
# vim: set tabstop=4 expandtab:
