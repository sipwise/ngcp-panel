package NGCP::Panel::Field::E164;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';


#has 'label' => ( default => 'E164 Number');

has_field 'cc' => (
    type => 'Text',
    element_attr => {
        class => ['ngcp_e164_cc'],
        rel => ['tooltip'],
        title => ['Country Code, e.g. 1 for US or 43 for Austria']
    },
    do_label => 0,
    do_wrapper => 0,
    #required => 1,
);

has_field 'ac' => (
    type => 'Text',
    element_attr => {
        class => ['ngcp_e164_ac'],
        rel => ['tooltip'],
        title => ['Area Code, e.g. 212 for NYC or 1 for Vienna']
    },
    do_label => 0,
    do_wrapper => 0,
    #required => 1,
);

has_field 'sn' => (
    type => 'Text',
    element_attr => {
        class => ['ngcp_e164_sn'],
        rel => ['tooltip'],
        title => ['Subscriber Number, e.g. 12345678']
    },
    do_label => 0,
    do_wrapper => 0,
    #required => 1,
);

sub validate {
    my $self = shift;
    my $c = $self->form->ctx;
    return unless($c);

    my $cc = $self->field('cc')->value;
    my $sn = $self->field('sn')->value;

    my @sub_fields = (qw/cc ac sn/);
    my %sub_errors =
        map { $_ => 1 }
            map { ($self->field($_) && $self->field($_)->result ) ? @{$self->field($_)->errors} : () }
                @sub_fields;
    for my $sub_error( keys %sub_errors ) {
        $self->add_error($sub_error);
    }
    for my $sub_field (@sub_fields){
        my $field = $self->field($sub_field);
        $field->clear_errors if $field && $field->result;
        my $has_field = (defined $field && defined $field->value) ? 1 : 0;
        my $len = $has_field ? length($field->value) : 0;
        my $pattern = $c->config->{number_format}->{$sub_field . "_regex"};

        # check for max size as set in DB schema
        if($sub_field eq "cc" && $len > 4) {
            $field->add_error("value must not exceed 4 digits but is $len");
        } elsif($sub_field eq "ac" && $len > 7) {
            $field->add_error("value must not exceed 7 digits but is $len");
        } elsif($sub_field eq "sn" && $len > 31) {
            $field->add_error("value must not exceed 31 digits but is $len");
        }

        # check for particular user-defined regex
        if($pattern && $has_field && $field !~ /$pattern/) {
            $field->add_error("value does not match required $sub_field pattern");
        }
    }

    if ($self->has_errors) {
        #don't add more errors
    } elsif (defined $cc && $cc ne '' && (!defined $sn || $sn eq '')) {
        my $err_msg = 'Subscriber Number required if Country Code is set';
        $self->add_error($err_msg);
    } elsif(defined $sn && $sn ne '' && (!defined $cc || $cc eq '')) {
        my $err_msg = 'Country Code required if Subscriber Number is set';
        $self->add_error($err_msg);
    }
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
