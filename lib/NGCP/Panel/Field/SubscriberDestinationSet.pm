package NGCP::Panel::Field::SubscriberDestinationSet;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    my $form = $self->form;

    return [] unless $form->ctx;

    my $destination_sets = $form->ctx->stash->{cf_destination_sets};
    my @all;
    return \@all unless($destination_sets);

    foreach my $set($destination_sets->all) {
        my $entry = {};
        $entry->{label} = $set->name;
        $entry->{value} = $set->id;
        push @all, $entry;
    }
    return \@all;
}

1;

# vim: set tabstop=4 expandtab:
