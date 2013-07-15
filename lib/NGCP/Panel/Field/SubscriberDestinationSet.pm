package NGCP::Panel::Field::SubscriberDestinationSet;
use Moose;
use Data::Printer;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    my $form = $self->form;

    my $active_destination_set = $form->ctx->stash->{cf_active_destination_set};
    my $destination_sets = $form->ctx->stash->{cf_destination_sets};

    my @all;
    foreach my $set($destination_sets->all) {
        my $entry = {};
        $entry->{label} = $set->name;
        $entry->{value} = $set->id;
        if($active_destination_set && 
           $set->id == $active_destination_set->id) {
            $entry->{active} = 1;
        }
        push @all, $entry;
    }

    return \@all;
}

1;

# vim: set tabstop=4 expandtab:
