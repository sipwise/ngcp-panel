package NGCP::Panel::Utils::API;
use strict;
use warnings;

use File::Find::Rule;


sub get_collections {
    my @files = @{get_collections_files()};
    my(@collections, @packages, @modules);
    foreach my $mod(@files) {
        # extract file base from path (e.g. Foo from lib/something/Foo.pm)
        $mod =~ s/^.+\/([a-zA-Z0-9_]+)\.pm$/$1/;
        my $package = 'NGCP::Panel::Controller::API::'.$mod;
        my $rel = lc $mod;
        $mod = 'NGCP::Panel::Controller::API::'.$mod;
        push @modules, $mod;
        push @packages, $package;
        push @collections, $rel;
    }
    return \@files, \@packages, \@collections, \@modules;
}
sub get_collections_files {
    my($library,$libpath) = @_;
    if(!$libpath){
        # figure out base path of our api modules
        $library ||= "NGCP/Panel/Controller/API/Root.pm";
        $libpath = $INC{$library};
        $libpath =~ s/\/[^\/]+$/\//;
    }
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
