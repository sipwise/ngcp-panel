package NGCP::Panel::Form::Intercept::Update;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'PosInteger',
    label => 'id',
    required => 1,
);

has_field 'data' => (
    type => 'Compound',
    label => 'data',
    required => 1,
    validate_when_empty => 1,
);

has_field 'data.cc_required' => (
    type => 'PosInteger',
    label => 'data.cc_required',
    range_start => 0,
    range_end => 1,
    required => 1,
);

has_field 'data.iri_delivery' => (
    type => 'Compound',
    label => 'data.iri_delivery',
    required => 1,
    validate_when_empty => 1,
);

has_field 'data.iri_delivery.host' => (
    type => 'Text',
    label => 'data.iri_delivery.host',
    required => 1,
);

has_field 'data.iri_delivery.port' => (
    type => 'PosInteger',
    label => 'data.iri_delivery.port',
    required => 1,
    range_start => 1,
    range_end => 65535,
);

has_field 'data.iri_delivery.username' => (
    type => 'Text',
    label => 'data.iri_delivery.username',
    required => 0,
);

has_field 'data.iri_delivery.password' => (
    type => 'Text',
    label => 'data.iri_delivery.password',
    required => 0,
);

has_field 'data.cc_delivery' => (
    type => 'Compound',
    required => 0,
    validate_when_empty => 0,
);

has_field 'data.cc_delivery.host' => (
    type => 'Text',
    label => 'data.cc_delivery.host',
    required => 1,
);

has_field 'data.cc_delivery.port' => (
    type => 'PosInteger',
    label => 'data.cc_delivery.port',
    required => 1,
    range_start => 1,
    range_end => 65535,
);


1;
# vim: set tabstop=4 expandtab:
