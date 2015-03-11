package NGCP::Panel::Field::SubscriberTimeSet;
use Sipwise::Base;
use parent 'HTML::FormHandler::Field::Select';

sub build_options {
    my ($self) = @_;

    my $form = $self->form;
    return [] unless $form->ctx;

    my $time_sets = $form->ctx->stash->{cf_time_sets};
    my @all;
    return \@all unless($time_sets);

    push @all, { label => '<always>', value => undef};
    foreach my $set($time_sets->all) {
        my $entry = {};
        $entry->{label} = $set->name;
        $entry->{value} = $set->id;
        push @all, $entry;
    }
    return \@all;
}

1;

# vim: set tabstop=4 expandtab:
