package NGCP::Panel::Form::Subscriber::SpeedDial;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'slot' => (
    type => 'Select',
    label => 'Slot',
    options_method => \&set_slots,
    required => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

sub set_slots {
    my($self) = @_;
    my @options = ();
    my @used = ();
    my $current;
    if(defined $self->form->ctx && 
       defined $self->form->ctx->stash->{used_sd_slots}) {
        foreach my $s($self->form->ctx->stash->{used_sd_slots}->all) {
            push @used, $s->slot;
        }
    }
    if(defined $self->form->ctx && 
       defined $self->form->ctx->stash->{speeddial}) {
        $current = $self->form->ctx->stash->{speeddial}->slot;
    }
    foreach my $s(@{ $self->form->ctx->config->{speed_dial_vsc_presets}->{vsc} })
    {
        if($s ~~ @used) {
            next unless(defined $current && $s eq $current);
        }
        push @options, { label => $s, value => $s };
    }
    return \@options;
}

has_field 'destination' => (
    type => 'Text',
    label => 'Destination',
    required => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);


has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/slot destination/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
