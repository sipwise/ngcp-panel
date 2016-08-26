package NGCP::Panel::Field::SubscriberSourceSet;
use Moose;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    my $form = $self->form;
    return [] unless $form->ctx;

    my $source_sets = $form->ctx->stash->{cf_source_sets};
    my @all;
    return \@all unless($source_sets);

    push @all, { label => '<all sources>', value => undef};
    foreach my $set($source_sets->all) {
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
