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
    unless (NGCP::Panel::Utils::DateTime::is_valid_timezone_name($value, 0, $c, 1)) {
        $self->add_error(sprintf 'Invalid timezone name: %s', $value);
    }
    return;
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
    $value = NGCP::Panel::Utils::DateTime::get_timezone_link($c, $value);
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
    my ($c) = @_;
    my ($tz_owner_parent_type,$tz_owner_parent_id) = ('', '');
    my $schema = $c->model('DB');
    if ($c->stash->{subscriber}) {
        $tz_owner_parent_type = 'contract';
        #billing subscriber
        $tz_owner_parent_id = $c->stash->{subscriber}->contract_id;
    } elsif ($c->stash->{contract}) {
        $tz_owner_parent_type = 'reseller';
        $tz_owner_parent_id = $c->stash->{contract}->contact->reseller_id // '';
    } elsif ($c->stash->{contact}) {
        #edit - we can rely on contact owner info
        my $contact_id = $c->stash->{contact}->id;
        my %timezones_spec = (
            'subscriber' => 'voip_subscriber_timezone',
            'contract' => 'contract_timezone');
        while (my($type,$result_set) = each %timezones_spec ) {
            if (my $owner_tz = $schema->resultset($result_set)->search_rs({contact_id => $contact_id})->first) {
                if ($type eq 'subscriber') {
                    $tz_owner_parent_type = 'contract';
                    #billing subscriber
                    $tz_owner_parent_id = $owner_tz->voip_subscriber->contract->id;
                } elsif ($type eq 'contract') {
                    $tz_owner_parent_type = 'reseller';
                    #billing subscriber
                    $tz_owner_parent_id = $owner_tz->contract->contact->reseller_id // '';
                }
                last;
            }
        }
    } elsif ($c->stash->{close_target}) {
        my $close_target = $c->stash->{close_target};
        if ($close_target =~m!/(contract|customer)(?:/[^0-9]+)?/([0-9]+)/!) {
            if ($close_target =~m!/subscriber/create/!) {
                $tz_owner_parent_type = 'contract';
                $tz_owner_parent_id = $2;
            } else {
                $tz_owner_parent_type = 'reseller';
                #it may be reseller contract
                $tz_owner_parent_id = $schema->resultset('contracts')->search_rs({id => $2})->first->contact->reseller_id;
                if (!$tz_owner_parent_id) {
                    #it is reseller contract
                    $tz_owner_parent_type = 'top';
                }
            }
        } elsif ($close_target =~m!/(subscriber)(?:/[^0-9]+)?/([0-9]+)/!) {
            $tz_owner_parent_type = 'contract';
            #billing subscriber
            $tz_owner_parent_id = $schema->resultset('voip_subscribers')->search_rs({id => $2})->first->contract_id;
        } elsif ($close_target =~m!/reseller/!) {
            $tz_owner_parent_type = 'top';
        }
    } else {
        $tz_owner_parent_type = 'noparentinfo';
    }
    return $tz_owner_parent_type, $tz_owner_parent_id;
}

no Moose;
1;
