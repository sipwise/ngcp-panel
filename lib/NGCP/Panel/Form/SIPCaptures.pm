package NGCP::Panel::Form::SIPCaptures;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has_field 'timestamp' => (
    type => 'Text',
    label => 'Timestamp',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Timestamp of the sip packet'],
    },
);

has_field 'protocol' => (
    type => 'Text',
    label => 'Protocol',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Protocol of the sip packet'],
    },
);

has_field 'src_ip' => (
    type => 'Text',
    label => 'Source IP',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Source IP of the sip packet'],
    },
);

has_field 'src_port' => (
    type => 'Text',
    label => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Source port of the sip packet'],
    },
);

has_field 'dst_ip' => (
    type => 'Text',
    label => 'Destination IP',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Destination IP of the sip packet'],
    },
);

has_field 'dst_port' => (
    type => 'PosInteger',
    label => 'Destination Port',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Destination port of the sip packet'],
    },
);

has_field 'method' => (
    type => 'Text',
    label => 'Method',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Method of the sip packet'],
    },
);

has_field 'cseq_method' => (
    type => 'Text',
    label => 'CSEQ Method',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['CSEQ Method of the sip packet'],
    },
);

has_field 'call_id' => (
    type => 'Text',
    label => 'Call ID',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Call id of the sip packet'],
    },
);

has_field 'from_uri' => (
    type => 'Text',
    label => 'From URI',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['From URI of the sip packet'],
    },
);

has_field 'request_uri' => (
    type => 'Text',
    label => 'Request URI',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Request URI of the sip packet'],
    },
);

1;

__END__

=head1 NAME

NGCP::Panel::Form::SIPCaptures

=head1 DESCRIPTION

A helper to manipulate the sip capture forms

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
