package NGCP::Panel::Form::ProvisioningTemplate;

use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

#has 'readonly' => (is   => 'rw',
#                   isa  => 'Int',
#                   default => 0,);

has 'fields_config' => (is => 'rw');

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body ngcp-modal-preferences/],
);

sub field_list {
    my $self = shift;

    return [] unless $self->ctx;

    my @field_list;
    my $fields_config = $self->fields_config;
    foreach my $field_config (@$fields_config) {
        my %field = %$field_config;
        $field{translate} //= 0;
        push(@field_list,\%field);
    }

    return \@field_list;
}

sub validate {
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    my $res = 1;

    #my $attribute = 'codecs_list';
    #if(my $field = $self->field( $attribute )){
    #    if( my $value = $field->value ){
    #        #todo: 1.Should we allow only some particular separator?
    #        #todo: 2.Lengths of the provisioning.voip_usr_preferences.value and kamailio.usr_preferences.value =128,all available values length is 141. We can't insert all codecs.
    #        my $enum = { map { lc( $_ ) => 1 } qw/AMR AMR-WB CelB CLEARMODE CN DVI4 G722 G723 G728 G729 GSM H261 H263 H263-1998 h264
    #            JPEG L16 MP2T MPA MPV nv opus PCMA PCMU QCELP speex telephone-event vp8 vp9/ };
    #        my @codecs = split(/,/, $value);
    #        my %codecs_dup;
    #        foreach my $codec( @codecs){
    #            $codec = lc($codec);
    #            if( !exists $enum->{$codec} ){
    #                my $err_msg = 'Value should be a comma separated list of the valid codecs.';
    #                $field->add_error($err_msg);
    #                $res = 0;
    #                last;
    #            }
    #            if($codecs_dup{$codec}){
    #                my $err_msg = 'Value should not contain duplicates.';
    #                $field->add_error($err_msg);
    #                $res = 0;
    #                last;
    #            }
    #            $codecs_dup{$codec} = 1;
    #        }
    #    }
    #}
    return $res;
}

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_field 'add' => (
    type => 'Submit',
    value => 'Add',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
    do_wrapper => 0,
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub create_structure {
    my $self = shift;
    my $field_list = shift;

    $self->block('fields')->render_list($field_list);
}

1;