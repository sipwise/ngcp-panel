package NGCP::Panel::Form::Customer::PbxFieldDeviceEdit;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Customer::PbxFieldDevice';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;


has_field 'line.line' => (
    type => 'Select',
    required => 1,
    label => 'Line/Key',
    options_method => \&build_lines,
    no_option_validation => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The line/key to use'],
    },
    element_class => [qw/ngcp-linekey-select/],
);
sub build_lines {
    my ($self) = @_;
    my $c = $self->form->ctx;
    return [] unless $c;
    my $fdev = $c->stash->{pbx_device};
    my @options = ();
    my $i = 0;
    foreach my $range($fdev->profile->config->device->autoprov_device_line_ranges->all) {
        push @options, { label => '', value => '' };
        for(my $j = 0; $j < $range->num_lines; ++$j) {
            push @options, { 
                label => $range->name . ' - Key/Line ' . $j,
                value => $range->id . '.' . $i . '.' . $j,
            };
        }
        $i++;
    }
    return \@options;
}

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/profile_id identifier station_name line line_add/],
);

1;
# vim: set tabstop=4 expandtab:
