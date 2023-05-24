package NGCP::Panel::Form::Invoice::TemplateAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Invoice::TemplateReseller';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    label => 'Reseller',
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id to assign this invoice template to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller name type call_direction category/],
);

sub validate {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless $c;
    
    my $category = $self->field('category')->value;
    my $reseller_id = $self->field('reseller')->value;
    $reseller_id = $reseller_id->{id} if $reseller_id;
    
    if (($category eq 'customer'
         or $category eq 'did')
        and not $reseller_id) {
        $self->field('reseller')->fields->[0]->add_error($c->loc("Reseller is required for category 'customer' or 'did'"));
    } elsif (($category eq 'peer'
         or $category eq 'reseller')
        and $reseller_id) {
        $self->field('reseller')->fields->[0]->add_error($c->loc("Reseller is must be empty for category 'peer' or 'reseller'"));
    }

}

1;

# vim: set tabstop=4 expandtab:
