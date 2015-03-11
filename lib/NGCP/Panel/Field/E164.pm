package NGCP::Panel::Field::E164;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Compound';


#has 'label' => ( default => 'E164 Number');

has_field 'cc' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        class => ['ngcp_e164_cc'], 
        rel => ['tooltip'], 
        title => ['Country Code, e.g. 1 for US or 43 for Austria'] 
    },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'ac' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        class => ['ngcp_e164_ac'], 
        rel => ['tooltip'], 
        title => ['Area Code, e.g. 212 for NYC or 1 for Vienna'] 
    },
    do_label => 0,
    do_wrapper => 0,
);

has_field 'sn' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        class => ['ngcp_e164_sn'], 
        rel => ['tooltip'], 
        title => ['Subscriber Number, e.g. 12345678'] 
    },
    do_label => 0,
    do_wrapper => 0,
);

sub validate {
    my $self = shift;
    my $cc = $self->field('cc')->value;
    my $sn = $self->field('sn')->value;

    my %sub_errors = map {$_, 1} (
        @{ $self->field('cc')->errors },
        @{ $self->field('ac')->errors },
        @{ $self->field('sn')->errors } );
    for my $sub_error( keys %sub_errors ) {
        $self->add_error($sub_error);
    }
    $self->field('cc')->clear_errors if $self->field('cc');
    $self->field('ac')->clear_errors if $self->field('ac');
    $self->field('sn')->clear_errors if $self->field('sn');

    if ($self->has_errors) {
        #dont add more errors
    } elsif (defined $cc && $cc ne '' && (!defined $sn || $sn eq '')) {
        my $err_msg = 'Subscriber Number required if Country Code is set';
        $self->add_error($err_msg);
    } elsif(defined $sn && $sn ne '' && (!defined $cc || $cc eq '')) {
        my $err_msg = 'Country Code required if Subscriber Number is set';
        $self->add_error($err_msg);
    }
}

1;

# vim: set tabstop=4 expandtab:
