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
    inflate_default_method => \&inflate_timezone,#from db to form
    deflate_value_method   => \&deflate_timezone,#from form to db
);

sub validate {
    my $self = shift;
    my $form = $self->form;
    my $c = $form->ctx;
    return unless $c;

    my $value = $self->value;
    if (ref $value && exists $value->{name}) {
        $value = $value->{name};
    } else {
        $self->add_error(
            sprintf 'Invalid validation of unparsed input: %s', $value);
        return;
    }
    #is_valid_timezone_name($tz, $all, $c, $allow_empty)
    #unless(grep { /^\Q$value\E$/ } DateTime::TimeZone->all_names) {
    $c->log->debug("validateimezone: 2");
    unless (NGCP::Panel::Utils::DateTime::is_valid_timezone_name($value, 0, $c, 1)) {
        $c->log->debug("not valid timezone");
        $self->add_error(sprintf 'Invalid timezone name: %s', $value);
    }
    $c->log->debug("validateimezone: 3");
    return 1;
}

sub adjust_datatable_vars {
    my ($self, $vars) = @_;
    my $form = $self->form;
    my $ctx = $form->ctx;
    return unless $ctx;
    my ($tz_owner_parent_type, $tz_owner_parent_id) = get_parent_info($ctx);
    $vars->{ajax_src} = (
        $ctx->uri_for_action('/contact/timezone_ajax', $tz_owner_parent_type, $tz_owner_parent_id)->as_string
    );
}

sub deflate_timezone {  # deflate: default value: clean and return empty string
    my ( $self, $value ) = @_;

    my $c = $self->form->ctx;
    $value = NGCP::Panel::Utils::DateTime::strip_empty_timezone_name($c, $value);
    return $value;
}

sub inflate_timezone {  # inflate: name empty timezone properly so it could be checked by form
    my ($self, $value) = @_;
    if (!$value) {
        my $c = $self->form->ctx;
        my ($parent_owner_type, $parent_owner_id) = get_parent_info($c);
        my $default_tz_data = NGCP::Panel::Utils::DateTime::get_default_timezone_name($c, $parent_owner_type, $parent_owner_id);
        $value = $default_tz_data->{name};
    }
    return $value;
}

sub get_parent_info {
    my ($ctx) = @_;
    my ($tz_owner_parent_type,$tz_owner_parent_id);
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
        $tz_owner_parent_id = '';
    }
    return $tz_owner_parent_type, $tz_owner_parent_id;
}

no Moose;
1;
