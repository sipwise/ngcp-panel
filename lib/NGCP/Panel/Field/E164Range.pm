package NGCP::Panel::Field::E164Range;
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
    required => 1,
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
    required => 0,
);

has_field 'snbase' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        class => ['ngcp_e164_snbase'], 
        rel => ['tooltip'], 
        title => ['Subscriber Base, e.g. 12345'] 
    },
    do_label => 0,
    do_wrapper => 0,
    required => 1,
);

has_field 'snlength' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        class => ['ngcp_e164_snlength'], 
        rel => ['tooltip'], 
        title => ['Subscriber Number Range Length (e.g. 2 for 1-212-12345xx'] 
    },
    do_label => 0,
    do_wrapper => 0,
    required => 1,
);

sub validate {
    my $self = shift;
    my $cc = $self->field('cc')->value;
    my $sn = $self->field('snbase')->value;
    my $snlen = $self->field('snlength')->value;

    my %sub_errors = map {$_, 1} (
        @{ $self->field('cc')->errors },
        @{ $self->field('ac')->errors },
        @{ $self->field('snbase')->errors },
        @{ $self->field('snlength')->errors } );
    for my $sub_error( keys %sub_errors ) {
        $self->add_error($sub_error);
    }
    $self->field('cc')->clear_errors if $self->field('cc');
    $self->field('ac')->clear_errors if $self->field('ac');
    $self->field('snbase')->clear_errors if $self->field('snbase');
    $self->field('snlength')->clear_errors if $self->field('snlength');

    if ($self->has_errors) {
        #dont add more errors
    } elsif (defined $cc && $cc ne '' && (!defined $sn || $sn eq '')) {
        my $err_msg = 'Subscriber Number required if Country Code is set';
        $self->add_error($err_msg);
    } elsif(defined $sn && $sn ne '' && (!defined $cc || $cc eq '')) {
        my $err_msg = 'Country Code required if Subscriber Number is set';
        $self->add_error($err_msg);
    }
    if(defined $sn && $sn ne '' && (!defined $snlen || $snlen eq '')) {
        my $err_msg = 'Subscriber Number Range Length required if Subscriber Base is set';
        $self->add_error($err_msg);
    }
}

1;

# vim: set tabstop=4 expandtab:
