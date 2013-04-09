package NGCP::Panel::Form::Preferences;

use HTML::FormHandler::Moose;
use Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;
use HTML::Entities qw/encode_entities/;

use HTML::FormHandler::Widget::Block::Bootstrap;

use Data::Printer;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/myfields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has 'readonly' => (is   => 'rw',
                   isa  => 'Int',
                   default => 0,);

has 'fields_data' => (is => 'rw');

has_block 'myfields' => (
    tag => 'div',
);

sub field_list {
    my $self = shift;
    
    my @field_list;
    my $fields_data = $self->fields_data;
   
    foreach my $row (@$fields_data) {
        my $data = $row->{data};
        my $enums = $row->{enums};
        my $field;
        if($data->data_type eq "enum") {
            my @options = map {{label => $_->label, value => $_->value}} @{ $enums };
            $field = { 
                name => $data->attribute, 
                type => 'Select', 
                options => \@options,
            };
        } elsif($data->data_type eq "boolean") {
            $field = {
                name => $data->attribute,
                type => 'Boolean',
            };
        } elsif($data->data_type eq "int") {
            $field = {
                name => $data->attribute,
                type => 'Integer',
            };
        } else { # string
            if($data->max_occur == 1) {
                $field = {
                    name => $data->attribute,
                    type => 'Text',
                };
            } else {
                # TODO: needs to be a list of values with the option
                # to delete old, add new
                $field = {
                    name => $data->attribute,
                    type => 'Text',
                };
            }
        }
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

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub create_structure {
    my $self = shift;
    my $field_list = shift;
    
    $self->block('myfields')->render_list($field_list);
}

1;
# vim: set tabstop=4 expandtab:
