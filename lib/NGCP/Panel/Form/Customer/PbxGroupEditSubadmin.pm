package NGCP::Panel::Form::Customer::PbxGroupEditSubadmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Customer::PbxGroupBase';

has_field 'alias_select' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Numbers',
    do_label => 0,
    do_wrapper => 0,
    required => 0,
    template => 'helpers/datatables_multifield.tt',
    ajax_src => '/invalid',
    table_titles => ['#', 'Number', 'Subscriber'],
    table_fields => ['id', 'number', 'subscriber_username'],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/pbx_extension pbx_hunt_policy pbx_hunt_timeout pbx_hunt_cancel_mode alias_select/],
);

sub update_fields {
#IMPORTANT! redefined sub update_fields with no super call disable call of the update_field_list and defaults methods
    my ($self) = @_;

    my $c = $self->ctx;
    return unless($c);

    if($self->field('alias_select')) {
        my $sub;
        if($c->stash->{pilot}) {
            $sub = $c->stash->{pilot};
        }

        if($sub) {
            $self->field('alias_select')->ajax_src(
                    $c->uri_for_action("/subscriber/aliases_ajax", [$sub->id])->as_string,
                );
        }
    }
    return;
}

1;
# vim: set tabstop=4 expandtab:
