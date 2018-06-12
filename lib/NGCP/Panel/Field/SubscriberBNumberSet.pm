package NGCP::Panel::Field::SubscriberBNumberSet;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    my $form = $self->form;
    return [] unless $form->ctx;

    my $sets = $form->ctx->stash->{cf_bnumber_sets};
    my @all;
    return \@all unless($sets);

    push @all, { label => '<any number>', value => undef};
    foreach my $set($sets->all) {
        my $entry = {};
        $entry->{label} = $set->name;
        $entry->{value} = $set->id;
        push @all, $entry;
    }
    return \@all;
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
