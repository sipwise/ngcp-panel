package NGCP::Panel::Form::Subscriber::TrustedSource;

use Sipwise::Base;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;
use Data::Validate::IP qw/is_ipv4 is_ipv6/;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'src_ip' => (
    type => 'Text',
    label => 'Source IP',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The source IP address.']
    },
);

has_field 'protocol' => (
    type => 'Select',
    label => 'Protocol',
    required => 1,
    options => [
        { label => 'UDP', value => 'UDP' },
        { label => 'TCP', value => 'TCP' },
        { label => 'TLS', value => 'TLS' },
        { label => 'ANY', value => 'ANY' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The transport protocol (one of UDP, TCP, TLS, ANY).']
    },
);

has_field 'from_pattern' => (
    type => 'Text',
    label => 'From Pattern',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['A regular expression matching the From URI.']
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
    render_list => [qw/src_ip protocol from_pattern/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_src_ip {
    my ($self, $field) = @_;

    my $ip = $field->value;
    unless(is_ipv4($ip) || is_ipv6($ip)) {
        $field->add_error("Invalid IPv4 or IPv6 address."); 
    }

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
