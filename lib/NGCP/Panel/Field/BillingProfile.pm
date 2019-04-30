package NGCP::Panel::Field::BillingProfile;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Profile',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/billing/ajax',
    table_titles => ['#', 'Reseller', 'Profile'],
    table_fields => ['id', 'reseller_name', 'name'],
    adjust_datatable_vars => \&adjust_datatable_vars,
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Billing Profile',
    element_class => [qw/btn btn-tertiary pull-right/],
);

sub adjust_datatable_vars {
    my ($self, $vars) = @_;
    my $form = $self->form;
    my $ctx = $form->ctx;
    return unless $ctx;
    my $type = $ctx->stash->{type} // '';
    if (grep {$type eq $_} (qw/reseller sippeering/)) {
        my $uri = ($ctx->uri_for_action('/billing/ajax')->as_string);
        $uri .= (($uri =~/\?/)?'&':'?'). 'no_prepaid_billing_profiles=1';
        $vars->{ajax_src} = $uri;
    }
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
