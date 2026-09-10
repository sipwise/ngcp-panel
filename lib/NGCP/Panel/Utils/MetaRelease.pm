package NGCP::Panel::Utils::MetaRelease;
use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(get_meta_release_data);
%EXPORT_TAGS = (
    DEFAULT => [qw(&get_meta_release_data)],
    all     => [qw(&get_meta_release_data)],
);

use English;

use Config::Tiny;
use DateTime::Format::Strptime;
use Digest::MD5 qw(md5_hex);
use JSON qw();
use LWP::UserAgent;

my $meta_release_url = 'https://deb.sipwise.com/meta-release';
my $cache_ttl = 3600;
my $cache_key = 'meta_release';

my $ngcp_version_file = '/etc/ngcp_version';
my $ngcp_roles_file = '/etc/default/ngcp-roles';

my $date_parser = DateTime::Format::Strptime->new(
    pattern   => '%a, %d %B %Y, %H:%M:%S %Z',
    time_zone => 'UTC',
);

sub read_ngcp_version {
    my $c = shift;

    open(my $fh, '<', $ngcp_version_file) or do {
        $c->log->debug("Cannot read file: $ngcp_version_file: $!");
        return;
    };

    my $version = <$fh>;

    return unless $version;

    chomp($version);
    close $fh;

    return $version;
}

sub read_ngcp_roles {
    my $c = shift;

    my $root = Config::Tiny->read($ngcp_roles_file, 'utf8');

    if (my $err = $Config::Tiny::errstr) {
        $c->log->debug("Error when reading $ngcp_roles_file: $err");
        return;
    }

    unless ($root->{_}) {
        $c->log->debug("Unexpected result from reading $ngcp_roles_file");
        return;
    }

    map { $root->{_}{$_} =~ s/(^['"]|['"]$)//g } keys %{$root->{_}};

    return $root->{_};;
}

sub read_meta_release_content {
    my ($c, $content) = @_;

    my $meta_release = Config::Tiny->read_string($content, 'utf8');

    if (my $err = $Config::Tiny::errstr) {
        $c->log->debug("Error when reading meta release content: $err");
        return;
    }

    my $parsed = {};

    my $ngcp_version = read_ngcp_version($c);
    my $ngcp_roles = read_ngcp_roles($c);

    return unless $ngcp_version;
    return unless $ngcp_roles;

    my $latest = $meta_release->{latest}->{Release} // '';
    my $latest_lts = $meta_release->{latest_lts}->{Release} // '';

    foreach my $key (keys %{$meta_release}) {
        my $data = $meta_release->{$key};
        next unless $key eq $ngcp_version ||
                    $key eq 'latest' ||
                    $key eq 'latest_lts' ||
                    $key eq $latest ||
                    $key eq $latest_lts;
        foreach my $sub (qw/Dist LTS Supported Expired Release/) {
            next unless exists $data->{$sub};
            my $ch_key = lc($sub);
            my $value = $data->{$sub};
            if ($ch_key eq 'lts' or $ch_key eq 'supported') {
                $value = ($value eq "1" or $value == 1) ? JSON::true : JSON::false;
            }
            $parsed->{$key}{$ch_key} = $value;
        }
        if ($data->{Expired}) {
            my $expires = $date_parser->parse_datetime($data->{Expired});
            $parsed->{$key}{expired} = $expires->epoch <= time ? JSON::true : JSON::false;
        }
        if ($data->{CE_Expired}) {
            my $ce_expires = $date_parser->parse_datetime($data->{CE_Expired});
            $parsed->{$key}{ce_expired} = $ce_expires->epoch <= time ? JSON::true : JSON::false;
        }
        foreach my $sub (qw/Date Expired CE_Expired/) {
            if ($data->{$sub}) {
                my $ch_key = $sub;
                $ch_key = $sub eq 'Expired' ? 'expires' : lc($ch_key);
                $ch_key = $sub eq 'CE_Expired' ? 'ce_expires' : lc($ch_key);
                my $date = $date_parser->parse_datetime($data->{$sub});
                my $iso8601 = $date->strftime('%Y-%m-%dT%H:%M:%SZ');
                $parsed->{$key}{$ch_key} = $iso8601;
                $parsed->{$key}{$ch_key . '_timestamp'} = $date->epoch;
                delete $parsed->{$key}{$sub};
            }
        }
    }

    $parsed->{this} = {
        release => $ngcp_version,
        type => $ngcp_roles->{NGCP_TYPE},
        available_types => [qw(spce sppro carrier)],
    };

    return $parsed;
}

sub fetch_meta_release_data {
    my $c = shift;

    my $cache  = $c->cache->get($cache_key) || {};
    my $now    = time;
    my $last_fetch_time = $cache->{last_fetch_time} // 0;

    my $expired = $last_fetch_time ? ($now - $last_fetch_time < $cache_ttl) : 1;
    if ($cache->{parsed} && !$expired) {
        return (1, $cache->{parsed});
    }

    my $ua = LWP::UserAgent->new(
        timeout => 10,
        ssl_opts => {
            verify_hostname => 0,
        },
    );

    my $response = $ua->get($meta_release_url);

    if ($response->code != 200) {
        $c->log->debug("Failed to fetch $meta_release_url " . $response->status_line);
        return (0, undef);
    }

    my $content = $response->content;
    my $md5sum  = md5_hex($content);

    if (!$cache->{md5sum} || $cache->{md5sum} ne $md5sum) {
        $cache->{content} = $content;
        $cache->{md5sum}  = $md5sum;
    }

    my $parsed = read_meta_release_content($c, $content);

    $cache->{last_fetch_time} = $now;
    $cache->{parsed} = $parsed;

    $c->cache->set($cache_key, $cache);

    return (1, $parsed);
}

sub get_meta_release_data {
    my $c = shift;

    my ($res, $data) = fetch_meta_release_data($c);

    return $res && $data ? $data : {};
}

1;

# vim: set tabstop=4 expandtab:
