package NGCP::Panel::Form::ValidatorBase;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has '+use_fields_for_input_without_param' => ( default => 1 );
has 'in'           => (is=>'rw',isa => 'HashRef');
has 'in_validated' => (is=>'rw',isa => 'HashRef');
has 'backend'      => (is=>'rw',isa => 'NGCP::Panel::Model::DB::Base');

sub remove_undef_in{
    my($self,$in) = @_;
    $in ||= $self->in();
    foreach ( keys %$in) { if(!( defined $in->{$_} )){ delete $in->{$_}; } };
    $self->in($in);
}
1;