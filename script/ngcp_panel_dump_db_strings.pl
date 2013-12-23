#!/usr/bin/env perl

use strict;
use warnings;
use NGCP::Schema qw();

my $filepath = shift;
unless ($filepath) {
    $filepath = "lib/NGCP/Panel/Utils/DbStrings.pm";
    print "No filepath specified, using $filepath\n";
}

my $s = NGCP::Schema->connect;

open(my $fh, ">", $filepath)
    or die "cannot open file $!";

print $fh <<HEADER_END;
package NGCP::Panel::Utils::DbStrings;

use warnings;
use strict;

sub localize {

HEADER_END

my $rs = $s->resultset('voip_preferences');

for my $row ($rs->all) {
    print $fh '    $c->loc("'.$row->label."\");\n"
        if ($row->label);
    #as for [...] -> need to quote this in db
    #print $fh '    $c->loc(\''.$row->description =~ s/'/\\'/rg =~ s/([\[\]])/~$1/rg ."');\n"
    print $fh '    $c->loc(\''.$row->description =~ s/'/\\'/rg =~ s/([\[\]])//rg ."');\n"
        if ($row->description);
}

print $fh <<FOOTER_END;

    return;
}

1;

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

FOOTER_END

close $fh;

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

=head1 COPYRIGHT

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
