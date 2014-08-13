package NGCP::Panel::Form::InterceptionAPI;

use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;
use Data::Validate::IP qw/is_ipv4 is_ipv6/;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'liid' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The LI ID for this interception.']
    },
);

has_field 'number' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number to intercept.']
    },
);

has_field 'x2_host' => (
    type => 'Text',
    required => 1,
    validate_method => \&validate_ip,
    element_attr => {
        rel => ['tooltip'],
        title => ['The IP address of the X-2 interface.']
    },
);

has_field 'x2_port' => (
    type => 'PosInteger',
    required => 1,
    range_start => 1,
    range_end => 65535,
    element_attr => {
        rel => ['tooltip'],
        title => ['The port of the X-2 interface.']
    },
);

has_field 'x2_user' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The username for authenticating on the X-2 interface.']
    },
);

has_field 'x2_password' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The password for authenticating on the X-2 interface.']
    },
);

has_field 'x3_required' => (
    type => 'Boolean',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether to also intercept call content via X-3 interface (false by default).']
    },
);

has_field 'x3_host' => (
    type => 'Text',
    required => 0,
    validate_method => \&validate_ip,
    element_attr => {
        rel => ['tooltip'],
        title => ['The IP address of the X-3 interface.']
    },
);

has_field 'x3_port' => (
    type => 'PosInteger',
    required => 0,
    range_start => 1,
    range_end => 65535,
    element_attr => {
        rel => ['tooltip'],
        title => ['The port of the X-3 interface.']
    },
);


has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/liid number x2_host x2_port x2_user x2_password x3_required x3_host x3_port/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_ip {
    my ($self, $field) = @_;

    my $ip = $field->value;
    unless(is_ipv4($ip) || is_ipv6($ip)) {
        $field->add_error("Invalid IPv4 or IPv6 address."); 
    }

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
