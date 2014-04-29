package NGCP::Panel::Utils::DateTime;

use Sipwise::Base;
use DateTime;
use DateTime::Format::ISO8601;

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

sub new_local {
    my %params;
    @params{qw/year month day hour minute second nanosecond/} = @_;
    foreach(keys %params){
        !defined $params{$_} and delete $params{$_};
    }
    return DateTime->new(
        time_zone => DateTime::TimeZone->new(name => 'local'),
        %params,
    );
}

1;

# vim: set tabstop=4 expandtab:
