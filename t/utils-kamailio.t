use strict;
use warnings;

use Test::More;

use_ok('NGCP::Panel::Utils::Kamailio');

# Mocked Catalyst context: config, log and the outbound_socket enum lookup.
{
    package Mock::Log;
    sub new { return bless { warn => [] }, shift }
    sub debug { }
    sub warn { my ($self, $msg) = @_; push @{$self->{warn}}, $msg; return }
}
{
    package Mock::Row;
    sub new { my ($class, %args) = @_; return bless {%args}, $class }
    sub label { return $_[0]{label} }
    sub value { return $_[0]{value} }
}
{
    package Mock::RS;
    sub new { my ($class, @rows) = @_; return bless [@rows], $class }
    sub all { return @{$_[0]} }
    sub first { return $_[0][0] }
}
{
    package Mock::Model;
    sub new { my ($class, $enum) = @_; return bless { enum => $enum }, $class }
    sub resultset { return $_[0] }
    sub search_rs {
        my ($self, $cond) = @_;
        my %values = map { $_ => 1 } @{$cond->{'me.value'}{-in}};
        return Mock::RS->new(
            map { Mock::Row->new(label => $_->[0]) }
            grep { defined $_->[1] && $values{$_->[1]} } @{$self->{enum}}
        );
    }
}
{
    package Mock::C;
    sub new {
        my ($class, %args) = @_;
        return bless { log => Mock::Log->new, %args }, $class;
    }
    sub config { return $_[0]{config} }
    sub log { return $_[0]{log} }
    sub model { return Mock::Model->new($_[0]{enum}) }
}

# Example: multi-site PRO, Wien (site 1) and Graz (site 2), panel running in Wien.
my $outbound_socket_enum = [
    ['default', undef],
    ['wien:sp:neth0:192.168.89.130:tcp', 'tcp:192.168.89.130:5060'],
    ['wien:sp:neth0:192.168.89.130:tls', 'tls:192.168.89.130:5061'],
    ['wien:sp:neth0:192.168.89.130:udp', 'udp:192.168.89.130:5060'],
    ['graz:sp:neth0:192.168.89.138:tcp', 'tcp:192.168.89.138:5060'],
    ['graz:sp:neth0:192.168.89.138:tls', 'tls:192.168.89.138:5061'],
    ['graz:sp:neth0:192.168.89.138:udp', 'udp:192.168.89.138:5060'],
    ['wien:extra_sock', 'udp:10.0.0.1:5070'],
    ['graz:extra_sock', 'udp:10.0.0.1:5070'],
    ['nosite:other', 'udp:10.0.0.2:5060'],
];
my $wien_lb = 'sip:lb@172.16.255.250:5060;lr';
my $graz_lb = 'sip:lb@172.17.255.250:5060;lr';
my $wien_lb_set60 = 'sip:lb@172.16.255.60:5060;lr';
my $graz_lb_set60 = 'sip:lb@172.17.255.60:5060;lr';
my $sites = {
    1 => { name => 'wien', role => 'active', key => 'wien', lb_uri => $wien_lb,
           cluster_sets => { 50 => $wien_lb, 60 => $wien_lb_set60, default => 50 } },
    2 => { name => 'graz', role => 'active', key => 'graz', lb_uri => $graz_lb,
           cluster_sets => { 50 => $graz_lb, 60 => $graz_lb_set60, default => 50 } },
};
my $multisite_config = {
    sip => { path => '<sip:172.16.255.250:5060;lr>' },
    cluster_sets => { 50 => $wien_lb, 60 => $wien_lb_set60, default => 50 },
    multisite => { site_id => 1, sites => $sites },
};

subtest 'select_lb_uri' => sub {
    my $sets = { 50 => 'sip:lb@a;lr', 60 => 'sip:lb@b;lr', default => 50 };
    is(NGCP::Panel::Utils::Kamailio::select_lb_uri($sets, 60, 'fb'), 'sip:lb@b;lr', 'explicit lbrtp_set');
    is(NGCP::Panel::Utils::Kamailio::select_lb_uri($sets, undef, 'fb'), 'sip:lb@a;lr', 'default set');
    is(NGCP::Panel::Utils::Kamailio::select_lb_uri($sets, 70, 'fb'), 'fb', 'unknown set falls back');
    is(NGCP::Panel::Utils::Kamailio::select_lb_uri({}, undef, 'fb'), 'fb', 'empty map falls back');
    is(NGCP::Panel::Utils::Kamailio::select_lb_uri(undef, 50, 'fb'), 'fb', 'missing map falls back');
    is(NGCP::Panel::Utils::Kamailio::select_lb_uri({ default => 50 }, undef, undef), undef, 'no fallback');
};

subtest 'site_from_socket_labels' => sub {
    my $f = \&NGCP::Panel::Utils::Kamailio::site_from_socket_labels;
    is(($f->($sites, 1, ['graz:sp:neth0:192.168.89.138:udp']))[0], 2, 'remote site');
    is(($f->($sites, 1, ['wien:sp:neth0:192.168.89.130:udp']))[0], 1, 'local site');
    is(($f->($sites, 1, ['wien:x', 'graz:y']))[0], 1, 'multiple sites: local preferred');
    is(($f->($sites, 3, ['wien:x', 'graz:y']))[0], undef, 'multiple remote sites: unresolved');
    is(($f->($sites, 1, ['nosite:other']))[0], undef, 'unknown site prefix');
    is(($f->($sites, 1, ['default']))[0], undef, 'label without prefix');
    is(($f->($sites, 1, []))[0], undef, 'no labels');
    is(($f->(undef, 1, ['wien:x']))[0], undef, 'no sites');
    my $no_key = { 1 => { name => 'wien' } };
    is(($f->($no_key, 1, ['wien:x']))[0], undef, 'site config without key (old templates)');
};

subtest '_compose_location_path' => sub {
    my $lbrtp_set;
    no warnings qw(redefine once);
    local *NGCP::Panel::Utils::Preferences::get_chained_preference_rs = sub {
        return Mock::RS->new(defined $lbrtp_set ? Mock::Row->new(value => $lbrtp_set) : ());
    };
    my $path = sub {
        my ($config, $socket, $enum) = @_;
        my $c = Mock::C->new(config => $config, enum => $enum // $outbound_socket_enum);
        return (NGCP::Panel::Utils::Kamailio::_compose_location_path($c, undef, { socket => $socket }), $c);
    };

    my ($p) = $path->($multisite_config, undef);
    is($p, '<sip:172.16.255.250:5060;lr>', 'no socket: default sip path');

    ($p) = $path->($multisite_config, 'sip:192.168.89.138:5060');
    is($p, "<$graz_lb;socket=sip:192.168.89.138:5060>", 'graz udp socket (web form sip:) from wien: graz LB');

    ($p) = $path->($multisite_config, 'udp:192.168.89.138:5060');
    is($p, "<$graz_lb;socket=udp:192.168.89.138:5060>", 'graz udp socket (API udp:) from wien: graz LB');

    ($p) = $path->($multisite_config, 'tls:192.168.89.138:5061');
    is($p, "<$graz_lb;socket=tls:192.168.89.138:5061>", 'graz tls socket: graz LB');

    ($p) = $path->($multisite_config, 'tcp:192.168.89.130:5060');
    is($p, "<$wien_lb;socket=tcp:192.168.89.130:5060>", 'wien socket: wien LB');

    ($p) = $path->($multisite_config, 'udp:10.0.0.1:5070');
    is($p, "<$wien_lb;socket=udp:10.0.0.1:5070>", 'socket in both sites: local LB');

    $lbrtp_set = 60;
    ($p) = $path->($multisite_config, 'sip:192.168.89.138:5060');
    is($p, "<$graz_lb_set60;socket=sip:192.168.89.138:5060>", 'lbrtp_set applied in the socket site');
    $lbrtp_set = 70;
    ($p) = $path->($multisite_config, 'sip:192.168.89.138:5060');
    is($p, "<$graz_lb;socket=sip:192.168.89.138:5060>", 'unknown lbrtp_set: site lb_uri');
    $lbrtp_set = undef;

    my $c;
    ($p, $c) = $path->($multisite_config, 'udp:198.51.100.1:5060');
    is($p, "<$wien_lb;socket=udp:198.51.100.1:5060>", 'socket not in enum: local LB');
    like($c->log->{warn}[0] // '', qr/cannot resolve site/, '... with warning');

    my $old_templates = { %{$multisite_config},
        multisite => { site_id => 1, sites => { 1 => { name => 'wien' }, 2 => { name => 'graz' } } } };
    ($p) = $path->($old_templates, 'sip:192.168.89.138:5060');
    is($p, "<$wien_lb;socket=sip:192.168.89.138:5060>", 'no per-site LB data: local LB');

    my $no_lb = { %{$multisite_config},
        multisite => { site_id => 1, sites => { %{$sites}, 2 => { key => 'graz' } } } };
    ($p, $c) = $path->($no_lb, 'sip:192.168.89.138:5060');
    is($p, "<$wien_lb;socket=sip:192.168.89.138:5060>", 'site without LB: local LB');
    like($c->log->{warn}[0] // '', qr/no LB configured for site 2/, '... with warning');

    my $single_site = { %{$multisite_config}, multisite => { site_id => 0 } };
    ($p) = $path->($single_site, 'udp:192.168.89.138:5060', []);
    is($p, "<$wien_lb;socket=udp:192.168.89.138:5060>", 'single site: unchanged behaviour');

    my $no_multisite = { cluster_sets => { default => 50 } };
    ($p) = $path->($no_multisite, 'udp:1.2.3.4:5060', []);
    is($p, '<sip:lb@127.0.0.1:5060;lr;socket=udp:1.2.3.4:5060>', 'no cluster sets: hardcoded fallback');
};

done_testing;
