package NGCP::Panel::Field::PosInteger;
use HTML::FormHandler::Moose;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Integer';

sub validate {
    my ( $self ) = @_;
    #use Data::Dumper;
    #use irka;
    #my $ctx = $self->ctx;
    #$ctx->log->debug(Dumper(["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"]));
    #irka::loglong(Dumper([caller]));
    #$ctx->log->debug(Dumper([caller]));
    my $value = $self->value;
    $self->add_error('Value must be a positive integer')
        if(!$self->has_errors && $value < 0);
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
