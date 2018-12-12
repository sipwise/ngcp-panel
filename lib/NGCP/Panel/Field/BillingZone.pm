package NGCP::Panel::Field::BillingZone;
use Moose;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Zone',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/billing/zones/ajax',
    adjust_datatable_vars => \&adjust_datatable_vars,
    table_titles => ['#', 'Zone', 'Zone Detail'],
    table_fields => ['id', 'zone', 'detail'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Zone',
    element_class => [qw/btn btn-tertiary pull-right/],
);

sub adjust_datatable_vars {
    my ($self, $vars) = @_;
    my $form = $self->form;
    my $ctx = $form->ctx;
    return unless $ctx;
    my $billing_profile_id = $ctx->stash->{profile}->{id};
    $vars->{ajax_src} = (
        $ctx->uri_for_action('/billing/zones_ajax', [$billing_profile_id])->as_string
    );
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
