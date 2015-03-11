package NGCP::Panel::Form::Domain::ResellerPbx;

use HTML::FormHandler::Moose;
use parent 'NGCP::Panel::Form::Domain::Reseller';

has_field 'rwr_set' => (
    type => 'Select',
    label => 'Rewrite Rule Set',
    options_method => \&build_rwr_sets,
    default => undef,
);

sub build_rwr_sets {
    my ($self) = @_;

    my $c = $self->form->ctx;
    my @options;

    push @options, { label => '', value => undef };
    if(defined $c) {
        my $sets = $c->stash->{reseller}->voip_rewrite_rule_sets;
        foreach my $s($sets->all) {
            push @options, { label => $s->name, value => $s->id };
        }
    }

    return \@options;
}

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/id domain rwr_set/],
);

1;
# vim: set tabstop=4 expandtab:
