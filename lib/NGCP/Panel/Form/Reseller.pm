package NGCP::Panel::Form::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

with 'HTML::FormHandler::Render::Table';

has '+widget_form' => (default => 'Table');

#sub build_form_tags {{ error_class => 'label label-secondary'}}

has_field 'id' => (
    type 'NonEditable',
);

has_field 'name' => (
    type 'Text',
);

has_field 'contract_id' => (
    type 'Integer',
);

has_field 'status' => (
    type 'Text',
);

1;
# vim: set tabstop=4 expandtab:
