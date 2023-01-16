package NGCP::Panel::Field::SubscriberDestinationSet;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    my $form = $self->form;

    return [] unless $form->ctx;

    my $destination_sets = $form->ctx->stash->{cf_destination_sets};
    my $subscriber_id = $form->ctx->stash->{subscriber}->provisioning_voip_subscriber->id;
    my @all;
    return \@all unless($destination_sets);

    foreach my $set($destination_sets->all) {
        my $entry = {};
        $entry->{label} = $set->name . ($subscriber_id != $set->subscriber_id ? ' (inherited)' : '');
        $entry->{value} = $set->id;
        push @all, $entry;
    }
    return \@all;
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
