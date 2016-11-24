package NGCP::Panel::Form::Event::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Event::Reseller';

has_field 'reseller_id' => (
    type => 'PosInteger',
    label => 'The subscriber contract\'s reseller.',
    required => 1,
);

has_field 'export_status' => (
    type => 'Select',
    label => 'The status of the exporting process.',
    options => [
        { label => 'unexported', 'value' => 'unexported' },
        { label => 'ok', 'value' => 'ok' },
        { label => 'failed', 'value' => 'failed' },
    ],
);

has_field 'exported_at' => (
    type => 'Text',
    title => 'The timestamp when the exporting occured.',
    required => 0,
);

1;
