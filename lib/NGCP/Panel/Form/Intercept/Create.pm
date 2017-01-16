package NGCP::Panel::Form::Intercept::Create;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'LIID' => (
    type => 'PosInteger',
    label => 'LIID',
    required => 1,
);

has_field 'number' => (
    type => 'Text',
    label => 'number',
    required => 1,
);

has_field 'cc_required' => (
    type => 'PosInteger',
    label => 'cc_required',
    range_start => 0,
    range_end => 1,
    required => 1,
);

has_field 'iri_delivery' => (
    type => 'Compound',
    label => 'iri_delivery',
    required => 1,
    validate_when_empty => 1,
);

has_field 'iri_delivery.host' => (
    type => 'Text',
    label => 'iri_delivery.host',
    required => 1,
);

has_field 'iri_delivery.port' => (
    type => 'PosInteger',
    label => 'iri_delivery.port',
    required => 1,
    range_start => 1,
    range_end => 65535,
);

has_field 'iri_delivery.username' => (
    type => 'Text',
    label => 'iri_delivery.username',
    required => 0,
);

has_field 'iri_delivery.password' => (
    type => 'Text',
    label => 'iri_delivery.password',
    required => 0,
);

has_field 'cc_delivery' => (
    type => 'Compound',
    required => 0,
    validate_when_empty => 0,
);

has_field 'cc_delivery.host' => (
    type => 'Text',
    label => 'cc_delivery.host',
    required => 1,
);

has_field 'cc_delivery.port' => (
    type => 'PosInteger',
    label => 'cc_delivery.port',
    required => 1,
    range_start => 1,
    range_end => 65535,
);


sub valprint {
    my($self, $field) = @_;
    my $c = $field->form->ctx;

    $c->log->info("validating " . $field->name . "=" . $field->value);
}

1;
# vim: set tabstop=4 expandtab:
