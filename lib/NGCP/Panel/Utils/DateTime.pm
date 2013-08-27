package NGCP::Panel::Utils::DateTime;

use Sipwise::Base;

sub current_local {
    return DateTime->now(
        time_zone => DateTime::TimeZone->new(name => 'local')
    );
}

sub epoch_local {
    my $epoch = shift;
    return DateTime->from_epoch(
        time_zone => DateTime::TimeZone->new(name => 'local'),
        epoch => $epoch,
    );
}

1;

# vim: set tabstop=4 expandtab:
