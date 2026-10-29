package NGCP::Panel::Utils::Contact;
use Sipwise::Base;

use Geography::Countries qw/countries country CNT_I_CODE2/;

sub list_countries {
    my ( $c, %params ) = @_;

    my $id = defined $params{id} ? uc $params{id} : undef;
    my $name = $params{name};
    my $q = $params{q};

    my @list;
    foreach my $country_name (countries) {
        my @cnt = country($country_name);
        my $code = $cnt[CNT_I_CODE2] or next;
        next if defined $id && $code ne $id;
        next if defined $name && $country_name !~ /\Q$name\E/i;
        next if defined $q && $code !~ /\Q$q\E/i && $country_name !~ /\Q$q\E/i;
        push @list, { id => $code, name => $country_name };
    }

    return \@list;
}

1;

# vim: set tabstop=4 expandtab:
