package NGCP::Panel::Form::PeeringServer;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;
use NGCP::Panel::Field::PosInteger;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => ( 
    type => 'Text',
    required => 1,
);

has_field 'ip' => (
    type => '+NGCP::Panel::Field::IPAddress',
    required => 1,
    label => 'IP Address',
);

has_field 'host' => (
    type => 'Text',
    label => 'Hostname',
);

has_field 'port' => (
    type => '+NGCP::Panel::Field::PosInteger',
    max_range => 65535,
    default => '5060',
    required => 1,
);

has_field 'transport' => (
    type => 'Select',
    label => 'Protocol',
    options => [
        { value => '1', label => 'UDP' },
        { value => '2', label => 'TCP' },
        { value => '3', label => 'TLS' },
    ],
);

has_field 'weight' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    range_end => 127,
    default => 1,
);

has_field 'via_route' => (
    type => 'Select',
    label => 'Via Route',
    options_method => \&build_via_routes,
);

sub build_via_routes {
    my ($self) = @_;

    my @options = ();
    push @options, { label => 'None', value => '' };
    my $sbcref = $self->form->ctx->config->{sip}->{external_sbc};
    if(defined $sbcref) {
        if(ref $sbcref eq "ARRAY") {
            foreach my $via(@{ $sbcref }) {
                my $uri = '<' . $via . ';lr>';
                push @options, { label => $uri, value => $uri };
            }
        } else {
            my $uri = '<' . $sbcref . ';lr>';
            push @options, { label => $uri, value => $uri };
        }
    }
    return \@options;
}

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/ name ip host port transport weight via_route /],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_via_route {
    my ($self, $field) = @_;

    my @hops = split /,/, $field->value;
    my $err = 0;
    foreach my $hop(@hops) {
        $hop =~ s/^\s*([^\s]+)\s*$/$1/;
        # TODO: is there a proper sip uri check?
        unless($hop =~ /^<sip\:.+>$/) {
            $err = 1; last;
        }
    }
    if($err) {
        $field->add_error("Invalid SIP URI, must be (comma-separated) SIP URI(s) in form sip:ip:port");
    }
}

1;

__END__

=head1 NAME

NGCP::Panel::Form::PeeringServer

=head1 DESCRIPTION

-

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
