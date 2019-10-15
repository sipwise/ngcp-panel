package NGCP::Panel::Field::Select;
use HTML::FormHandler::Moose;

extends 'HTML::FormHandler::Field::Select';

has 'translate' => (isa => 'Bool', is => 'rw', default => 1 );

no Moose;
1;
