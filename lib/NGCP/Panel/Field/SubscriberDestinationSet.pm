package NGCP::Panel::Field::SubscriberDestinationSet;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    my $form = $self->form;
    return [] unless $form->ctx;

    my $active_destination_set = $form->ctx->stash->{cf_active_destination_set};
    my $destination_sets = $form->ctx->stash->{cf_destination_sets};

    my @all;
    return \@all unless($destination_sets);
    push @all, { label => '', value => undef}
        unless($active_destination_set);
    foreach my $set($destination_sets->all) {
        my $entry = {};
        $entry->{label} = $set->name;
        $entry->{value} = $set->id;

        if($active_destination_set && 
           $set->id == $active_destination_set->id) {
            $entry->{selected} = 1;
        }
        push @all, $entry;
    }

    return \@all;
}

1;

# vim: set tabstop=4 expandtab:
