#!/usr/bin/env perl

use strict;
use warnings;
use NGCP::Schema qw();
use lib;
use NGCP::Panel::Utils::I18N;

my $filepath = shift;
unless ($filepath) {
    $filepath = "lib/NGCP/Panel/Utils/DbStrings.pm";
    print "No filepath specified, using $filepath\n";
}

my $s = NGCP::Schema->connect;

open(my $fh, ">", $filepath)
    or die "cannot open file $!";

print $fh <<'HEADER_END';
package NGCP::Panel::Utils::DbStrings;

use warnings;
use strict;

sub localize {
    my $c = shift;

HEADER_END

my $rs = $s->resultset('voip_preferences');

for my $row ($rs->all) {
    print $fh _string_to_line($row->label)
        if ($row->label);
    #as for [...] -> need to quote this in db
    #print $fh '    $c->loc(\''.$row->description =~ s/'/\\'/rg =~ s/([\[\]])/~$1/rg ."');\n"
    print $fh _string_to_line($row->description)
        if ($row->description);
}

for my $row ($s->resultset('voip_preference_groups')->all) {
    print $fh _string_to_line($row->name)
        if ($row->name);
}

print $fh "    return;\n}\n\nsub form_strings {\n    my \$c;\n\n";

my $path = 'lib/NGCP/Panel/Form/*.pm lib/NGCP/Panel/Form/*/*.pm';
my @files = < $path >;
my $dummy = (bless {}, "dummy");
sub dummy::loc { shift; return shift; };
my %unique_strings;
foreach my $mod(@files){
    my $modname = $mod =~ s!lib/!!r =~ s!/!::!gr =~ s!\.pm$!!r;
    if (eval "require $modname; 1;") {
        eval {
            my $form = $modname->new;
            my $strings = NGCP::Panel::Utils::I18N->translate_form($dummy, $form, 1);
            print $fh "    #$modname\n";
            @unique_strings{@$strings} = 1;
        } || print $fh " #$modname: error: $@\n";
    } else {
        print $fh "#'$modname' could not be loaded. Skipping it...\n";
    }
}

for my $s (keys %unique_strings) {
    next unless $s;
    next if $s =~ /^\d+?$/;
    print $fh _string_to_line($s);
}

print $fh <<FOOTER_END;

    return;
}

1;

=head1 NAME

NGCP::Panel::Utils::DbStrings

=head1 VERSION

Version UNRELEASED_VERSION

=head1 SYNOPSIS

Localization strings from DB and Forms

=head1 DESCRIPTION

Dump strings from DataBase and Forms to a dummy module, for localisation.
Strings are collected later by extract_i18n.sh script.

=head1 AUTHOR

Sipwise Development Team <support\@sipwise.com>

=head1 LICENSE

This software is Copyright 2021 by Sipwise GmbH, Austria.

All rights reserved. You may not copy, distribute
or modify without prior written permission from
Sipwise GmbH, Austria.

=cut

FOOTER_END

close $fh;

sub _string_to_line {
    my $string = shift;
    return '    $c->loc(\'' . $string =~ s/'/\\'/rg =~ s/([\[\]])/~$1/rg ."');\n";
}

__END__

=head1 NAME

ngcp_panel_dump_db_strings.pl

=head1 SYNOPSIS

ngcp_panel_dump_db_strings.pl [filename]

filename is optional. It will try to use lib/NGCP/Panel/Utils/DbStrings.pm
if none is specified.

=head1 DESCRIPTION

Dump Strings from database to a dummy module, for localisation.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
