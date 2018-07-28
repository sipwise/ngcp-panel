package NGCP::Panel::Field::TimezoneSelect;

use HTML::FormHandler::Moose;
use NGCP::Panel::Utils::DateTime;
extends 'HTML::FormHandler::Field::Compound';

has_field 'name' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Timezone',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/contact/timezone_ajax',
    table_titles => ['Name'],
    table_fields => ['name'],
    adjust_datatable_vars => \&adjust_datatable_vars,
);

sub validate {
    my $self = shift;
    my $value = $self->value;
    if (ref $value && exists $value->{name}) {
        $value = $value->{name};
    } else {
        $self->add_error(
            sprintf 'Invalid validation of unparsed input: %s', $value);
        return;
    }

    #unless(grep { /^\Q$value\E$/ } DateTime::TimeZone->all_names) {
    unless (NGCP::Panel::Utils::DateTime::is_valid_timezone_name($value)) {
        $self->add_error(sprintf 'Invalid timezone name: %s', $value);
    }
    return;
}

sub adjust_datatable_vars {
    my ($self, $vars) = @_;
    my ($tz_owner_parent_type, $tz_owner_parent_id);
    my $form = $self->form;
    my $ctx = $form->ctx;
    return unless $ctx;

    if ($ctx->stash->{subscriber}) {
        $tz_owner_parent_type //= 'contract';
        #billing subscriber
        $tz_owner_parent_id //= $ctx->stash->{subscriber}->contract_id;
    } elsif ($ctx->stash->{contract}) {
        $tz_owner_parent_type //= 'reseller';
        $tz_owner_parent_id //= $ctx->stash->{contract}->contact->reseller_id;        
    } else {
        $tz_owner_parent_type //= 'reseller';
        #we don't need id as we will not take reseller's parent
        #reseller is on the top and will use local as default
    }
    $vars->{ajax_src} = (
        $ctx->uri_for_action('/contact/timezone_ajax', $tz_owner_parent_type, $tz_owner_parent_id)->as_string
    );
}

no Moose;
1;
