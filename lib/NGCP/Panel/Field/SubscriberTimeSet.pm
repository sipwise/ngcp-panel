package NGCP::Panel::Field::SubscriberTimeSet;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    my $form = $self->form;
    return [] unless $form->ctx;

    my $time_sets = $form->ctx->stash->{cf_time_sets};
    my $subscriber_id = $form->ctx->stash->{subscriber}->provisioning_voip_subscriber->id;

    my @all;
    return \@all unless($time_sets);

    push @all, { label => '<always>', value => undef};
    foreach my $set($time_sets->all) {
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
