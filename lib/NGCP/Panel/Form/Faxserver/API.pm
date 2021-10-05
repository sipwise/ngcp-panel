package NGCP::Panel::Form::Faxserver::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use NGCP::Panel::Utils::Form qw();

has_field 'name' => (
    type => 'Text',
    label => 'Name in Fax Header',
    required => 0,
);


has_field 'password' => (
    type => 'Text',
    label => 'Password',
    required => 0,
);

sub validate_password {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    NGCP::Panel::Utils::Form::validate_password(c => $c, field => $field);
    return;
}

has_field 'active' => (
    type => 'Boolean',
    label => 'Active',
    required => 0,
);

has_field 'destinations' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
);

has_field 'destinations.destination' => (
    type => 'Text',
    label => 'Destination Email',
    required => 1,
);

has_field 'destinations.filetype' => (
    type => 'Select',
    options => [
        { label => 'TIFF', value => 'TIFF' },
        { label => 'PS', value => 'PS' },
        { label => 'PDF', value => 'PDF' },
        { label => 'PDF14', value => 'PDF14' },
    ],
    label => 'File Type',
    required => 1,
);

has_field 'destinations.incoming' => (
    type => 'Boolean',
    label => 'Deliver Incoming Faxes',
    default => 1,
);

has_field 'destinations.outgoing' => (
    type => 'Boolean',
    label => 'Deliver Outgoing Faxes',
    default => 1,
);

has_field 'destinations.status' => (
    type => 'Boolean',
    label => 'Receive Reports',
    default => 1,
);

has_field 't38' => (
    type => 'Boolean',
    label => 'T38',
    required => 0,
);

has_field 'ecm' => (
    type => 'Boolean',
    label => 'ECM',
    required => 0,
);

1;

# vim: set tabstop=4 expandtab:
