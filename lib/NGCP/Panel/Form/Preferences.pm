package NGCP::Panel::Form::Preferences;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has 'readonly' => (is   => 'rw',
                   isa  => 'Int',
                   default => 0,);

has 'fields_data' => (is => 'rw');

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body ngcp-modal-preferences/],
);

sub field_list {
    my $self = shift;

    return [] unless $self->ctx;
    my $is_subscriber = ($self->ctx->user->roles eq 'subscriber' || 
                         $self->ctx->user->roles eq 'subscriberadmin');
    
    my @field_list;
    my $fields_data = $self->fields_data;
   
    foreach my $row (@$fields_data) {
        my $meta = $row->{meta};
        my $enums = $row->{enums};
        my $rwrs_rs = $row->{rwrs_rs};
        my $ncos_rs = $row->{ncos_rs};
        my $sound_rs = $row->{sound_rs};
        my $contract_sound_rs = $row->{contract_sound_rs};
        my $field;
        if($meta->attribute eq "rewrite_rule_set") {
            my @options = map {{label => $_->name, value => $_->id}}
                defined $rwrs_rs ? $rwrs_rs->all : ();
            unshift @options, {label => '', value => ''};
            $field = {
                name => $meta->attribute,
                type => 'Select',
                options => \@options,
            };
        } elsif ($meta->attribute eq "ncos" ||
                 $meta->attribute eq "adm_ncos" ||
                 $meta->attribute eq "adm_cf_ncos") {
            my @options = map {{label => $_->level, value => $_->id}}
                defined $ncos_rs ? $ncos_rs->all : ();
            unshift @options, {label => '', value => ''};
            $field = {
                name => $meta->attribute,
                type => 'Select',
                options => \@options,
            };
        } elsif ($meta->attribute eq "sound_set") {
            my @options = map {{label => $_->name, value => $_->id}}
                defined $sound_rs ? $sound_rs->all : ();
            unshift @options, {label => '', value => ''};
            $field = {
                name => $meta->attribute,
                type => 'Select',
                options => \@options,
            };
        } elsif ($meta->attribute eq "contract_sound_set") {
            my @options = map {{label => $_->name, value => $_->id}}
                defined $contract_sound_rs ? $contract_sound_rs->all : ();
            unshift @options, {label => '', value => ''};
            $field = {
                name => $meta->attribute,
                type => 'Select',
                options => \@options,
            };
        } elsif($meta->data_type eq "enum") {
            my @options = map {{label => $_->label, value => $_->value}} @{ $enums };
            $field = { 
                name => $meta->attribute, 
                type => 'Select', 
                options => \@options,
            };
        } elsif($meta->data_type eq "boolean") {
            $field = {
                name => $meta->attribute,
                type => 'Boolean',
            };
        } elsif($meta->data_type eq "int") {
            $field = {
                name => $meta->attribute,
                type => 'Integer',
            };
        } else { # string
            if($meta->max_occur == 1) {
                $field = {
                    name => $meta->attribute,
                    type => 'Text',
                };
            } else {
                # is only used to add a new field
                $field = {
                    name => $meta->attribute,
                    type => 'Text',
                    do_label => 0,
                    do_wrapper => 1,
                    element_attr => {
                        class => ['ngcp_pref_input'],
                    }
                };
            }
        }
        $field->{label} = $is_subscriber ? $meta->label : $meta->attribute;
        push @field_list, $field;
    }
    
    return \@field_list;
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

__END__

=head1 NAME

NGCP::Panel::Form::Preferences

=head1 DESCRIPTION

Preferences Form.

=head1 METHODS

=head2 build_render_list

Specifies the order, form elements are rendered.

=head2 build_form_element_class

for styling

=head2 field_list

This is automatically called by the constructor, it allows you to create a number of fields that should be created.

=head2 create_structure

The field list given to this method will be rendered.

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
