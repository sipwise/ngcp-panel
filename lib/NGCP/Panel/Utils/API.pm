package NGCP::Panel::Utils::API;
use strict;
use warnings;

use File::Find::Rule;


sub get_collections {
    my $files = get_collections_files;
    foreach my $mod(@files) {
        # extract file base from path (e.g. Foo from lib/something/Foo.pm)
        $mod =~ s/^.+\/([a-zA-Z0-9_]+)\.pm$/$1/;
        my $rel = lc $mod;
        $mod = 'NGCP::Panel::Controller::API::'.$mod;
        my $dp = $mod->dispatch_path;
        push @links, Link => '<'.$dp.'>; rel="collection http://purl.org/sipwise/ngcp-api/#rel-'.$rel.'"';
    }
    
}
sub get_collections_files {

    # figure out base path of our api modules
    my $libpath = $INC{"NGCP/Panel/Controller/API/Root.pm"};
    $libpath =~ s/Root\.pm$//;

    # find all modules not called Root.pm and *Item.pm
    # (which should then be just collections)
    my $rootrule = File::Find::Rule->new->name('Root.pm');
    my $itemrule = File::Find::Rule->new->name('*Item.pm');
    my $rule = File::Find::Rule->new
        ->mindepth(1)
        ->maxdepth(1)
        ->name('*.pm')
        ->not($rootrule)
        ->not($itemrule);
    my @colls = $rule->in($libpath);

    return \@colls;
}

1;

=head1 NAME

NGCP::Panel::Utils::API

=head1 DESCRIPTION

A helper to manipulate REST API related data

=head1 METHODS

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
