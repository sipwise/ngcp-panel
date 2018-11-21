package NGCP::Panel::Form::Sound::LoadDefaultBase;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use File::Find::Rule;

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
    required => 0,
);

sub build_langs {
    my ($self) = @_;

    my @options = ();
    my @dirs = File::Find::Rule
        ->directory
        ->maxdepth(1)
        ->not(File::Find::Rule->new->name(qr/^\.\.?$/))
        ->in('/var/lib/ngcp-soundsets/system');

    @options = map { my $val = s/^.+\///r; { label => $val, value => $val } } @dirs;
        
    return \@options;
}


has_field 'loopplay' => (
    type => 'Boolean',
    label => 'Play in Loop',
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether to play files in a loop where applicable.']
    },
    required => 0,
);

has_field 'replace_existing' => (
    type => 'Boolean',
    label => 'Replace existing',
    element_attr => {
        rel => ['tooltip'],
        title => ['Replace existing sound files in set by default files.']
    },
    required => 0,
);

1;