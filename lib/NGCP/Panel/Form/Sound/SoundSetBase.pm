package NGCP::Panel::Form::Sound::SoundSetBase;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the sound set'],
    },
);

has_field 'description' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['The description of the sound set'],
    },
);

has_field 'contract_default' => (
    type => 'Boolean',
    label => 'Default for Subscribers',
    element_attr => {
        rel => ['tooltip'],
        title => ['If active (and a customer is selected), this sound set is used for all existing and new subscribers within this customer if no specific sound set is specified for the subscribers'],
    },
);

has_field 'copy_from_default' => (
    type => 'Boolean',
    label => 'Use system default sound files',
);

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
);

has_field 'override' => (
    type => 'Boolean',
    label => 'Replace existing',
    element_attr => {
        rel => ['tooltip'],
        title => ['Replace existing sound files in set by default files.']
    },
);

1;