package NGCP::Panel::Form::Sound::LoadDefault;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;
use File::Find::Rule;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'language' => (
    type => 'Select',
    label => 'Language',
    options_method => \&build_langs,
    default => 'en',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The language of the default sound files.']
    },
);

sub build_langs {
    my ($self) = @_;

    my @options = ();
    my @dirs = File::Find::Rule
        ->directory
        ->maxdepth(1)
        ->not(File::Find::Rule->new->name(qr/^\.\.?$/))
        ->in('/var/lib/ngcp-soundsets/system');

    @options = map { $_ =~ s/^.+\///; { label => $_, value => $_ } } @dirs;
        
    return \@options;
}


has_field 'loopplay' => (
    type => 'Boolean',
    label => 'Play in Loop',
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether to play files in a loop where applicable.']
    },
);

has_field 'override' => (
    type => 'Boolean',
    label => 'Replace existing',
    element_attr => {
        rel => ['tooltip'],
        title => ['Replace existing sound files in set by default files.']
    },
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
    render_list => [qw/language loopplay override/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
