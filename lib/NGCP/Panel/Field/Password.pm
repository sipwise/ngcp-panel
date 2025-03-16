package NGCP::Panel::Field::Password;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Password';

sub fif {
    my ( $self, $result ) = @_;
    return if ( $self->inactive && !$self->_active );
    #return '' if $self->password;
    return unless $result || $self->has_result;
    my $lresult = $result || $self->result;
    if ( ( $self->has_result && $self->has_input && !$self->fif_from_value ) ||
        ( $self->fif_from_value && !defined $lresult->value ) )
    {
        return defined $lresult->input ? $lresult->input : '';
    }
    if ( $lresult->has_value ) {
        my $value;
        if( $self->_can_deflate ) {
            $value = $self->_apply_deflation($lresult->value);
        }
        else {
            $value = $lresult->value;
        }
        return ( defined $value ? $value : '' );
    }
    elsif ( defined $self->value ) {
        # this is because checkboxes and submit buttons have their own 'value'
        # needs to be fixed in some better way
        return $self->value;
    }
    return '';
}

no Moose;
1;
