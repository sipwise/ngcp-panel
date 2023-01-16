package NGCP::Panel::Field::SubscriberSourceSet;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    my $form = $self->form;
    return [] unless $form->ctx;

    my $source_sets = $form->ctx->stash->{cf_source_sets};
    my $subscriber_id = $form->ctx->stash->{subscriber}->provisioning_voip_subscriber->id;

    my @all;
    return \@all unless($source_sets);

    push @all, { label => '<all sources>', value => undef};
    foreach my $set($source_sets->all) {
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
