# Rudimentary test of the javascript invocation in provisioning templates.
# It drives the real NGCP::Panel::Utils::ProvisioningTemplates code paths
# (provision_begin, _init_row_context, _calculate, provision_cleanup) with a
# mocked catalyst context, so no database is touched. Run it on an NGCP host:
#
#   perl -Ilib sandbox/test_provisioning_templates_js.pl

use strict;
use warnings;
use utf8;

use Test::More;
use DateTime qw();
use NGCP::Panel::Utils::ProvisioningTemplates qw();

binmode(Test::More->builder->$_, ':encoding(UTF-8)') for qw(output failure_output todo_output);

package MockLog {
    sub new { my ($class, $logs) = @_; return bless { logs => $logs }, $class; }
    foreach my $level (qw(debug info warn error)) {
        no strict 'refs'; ## no critic (ProhibitNoStrict)
        *{$level} = sub { my $self = shift; push(@{$self->{logs}}, [ $level, @_ ]); return 1; };
    }
}

package MockSchema {
    sub new { return bless {}, shift; }
    sub set_transaction_isolation { return; }
}

package MockC {
    sub new {
        my ($class, %template) = @_;
        return bless {
            stash => {
                provisioning_template_name => 'test',
                provisioning_templates => { test => \%template },
            },
            logs => [],
        }, $class;
    }
    sub stash { return shift->{stash}; }
    sub model { return MockSchema->new(); }
    sub log { my $self = shift; return MockLog->new($self->{logs}); }
}

package main;

my $engine = (defined &JavaScript::QuickJS::new) ? 'QuickJS' : 'JE';
diag("javascript engine: $engine");

my $c = MockC->new(
    lang => 'js',
    fields => [
        { name => 'cc_ac_map', type => 'calculated', value => { 43 => { 1 => 1, 316 => 1 }, 49 => { 89 => 1 } } },
        { name => 'cli', type => 'text' },
        { name => 'name', type => 'text' },
        { name => 'count', type => 'text' },
        # calculated fields see the row values in scope ...
        { name => 'e164', type => 'calculated', value_code => 'function() { return "43" + row.cli; }' },
        # ... including the ones calculated before
        { name => 'e164_split', type => 'calculated', value_code => 'function() { var n = split_number(row.e164); return n.cc + "/" + n.ac + "/" + n.sn; }' },
        { name => 'name_upper', type => 'calculated', value_code => 'function() { return row.name.toUpperCase(); }' },
        { name => 'count_plus', type => 'calculated', value_code => 'function() { return row.count + 1; }' },
        { name => 'count_num', type => 'calculated', value_code => 'function() { return parseInt(row.count) + 1; }' },
    ],
);

my $context = NGCP::Panel::Utils::ProvisioningTemplates::provision_begin(c => $c);
ok($context, 'provision_begin');

# row 1: field values arrive in the "row" scope variable
my $name = "O'Brien \\ \"Grüße\" 😀";
NGCP::Panel::Utils::ProvisioningTemplates::_init_row_context($c, $context, MockSchema->new(), {
    cli => '316123456', name => $name, count => '5',
});
my $row = $context->{row};
is($row->{e164}, '43316123456', 'row: calculated field uses row value');
is($row->{e164_split}, '43/316/123456', 'row: calculated field uses earlier calculated field and split_number() properties');
is($row->{name_upper}, uc($name), 'row: quotes, backslashes and non-ascii pass through');
is($row->{count_plus}, '51', 'row: plain values arrive as strings');
is($row->{count_num}, 6, 'row: number returned');

# row 2: the same engine is reused and "row" is reassigned
NGCP::Panel::Utils::ProvisioningTemplates::_init_row_context($c, $context, MockSchema->new(), {
    cli => '89123', name => 'x', count => '1',
});
is($context->{row}->{e164}, '4389123', 'row 2: row variable updated');

# entity fields, like subscriber/preferences templates
$context->{subscriber} = { username => 'john', id => 5, aliases => [ '1', '2' ], create_timestamp => DateTime->now };
sub calc {
    my ($col, $code) = @_;
    my ($k, $v) = NGCP::Panel::Utils::ProvisioningTemplates::_calculate($context, $col, $code);
    return $v;
}
is(calc(username_code => 'function() { return subscriber.username + "@" + row.cli; }'), 'john@89123', 'context hash in scope');
is(calc(aliases_code => 'function() { return subscriber.aliases.length; }'), 2, 'context array in scope');
is_deeply([ NGCP::Panel::Utils::ProvisioningTemplates::_calculate($context, subscriber => {
    username_code => 'function() { return row.name + "_user"; }',
    domain => 'example.org',
}) ], [ subscriber => { username => 'x_user', domain => 'example.org' } ], 'hash template');
is_deeply([ NGCP::Panel::Utils::ProvisioningTemplates::_calculate($context, registrations => [
    { contact_code => 'function() { return "sip:" + row.cli + "@1.2.3.4"; }' },
]) ], [ registrations => [ { contact => 'sip:89123@1.2.3.4' } ] ], 'array template');

# return value demarshalling
is(calc(s_code => 'function() { return "text"; }'), 'text', 'return string');
is(calc(i_code => 'function() { return 42; }'), 42, 'return integer');
is(calc(d_code => 'function() { return 1.5; }'), 1.5, 'return decimal');
is(calc(t_code => 'function() { return 1 == 1; }'), 1, 'return true as 1');
is(calc(f_code => 'function() { return false; }'), 0, 'return false as 0');
is(calc(n_code => 'function() { return null; }'), undef, 'return null as undef');
is(calc(u_code => 'function() { return undefined; }'), undef, 'return undefined as undef');
is_deeply(calc(o_code => 'function() { return { a: [ 1, "b", null, true ], b: { c: false }, d: null }; }'),
    { a => [ 1, 'b', undef, 1 ], b => { c => 0 }, d => undef }, 'return nested object with nulls and booleans');
is(calc(dt_code => 'function() { return new Date(Date.UTC(2026, 0, 1)); }'), 1767225600, 'return Date as epoch seconds');
is_deeply(calc(sn_code => 'function() { return split_number("4989123"); }'),
    { cc => '49', ac => '89', sn => '123' }, 'return split_number() object');
is(calc(now_code => 'function() { return now.getFullYear(); }'), DateTime->now->year, 'now is a Date');

# helpers
is(calc(h_code => 'function() { return sprintf("%05d-%s", 42, trim("  x  ")) + quotemeta("a.b"); }'), '00042-xa\\.b', 'sprintf, trim, quotemeta');
@{$c->{logs}} = ();
calc(l_code => 'function() { info("hello", 42); return 1; }');
is_deeply((grep { $_->[0] eq 'info'; } @{$c->{logs}})[0], [ 'info', 'hello', 42 ], 'info() reaches the log');

# errors
eval { calc(die_code => 'function() { die("custom error"); }'); };
like($@, qr/^die_code: custom error/, 'die() stops with the message');
eval { calc(throw_code => 'function() { throw new Error("js boom"); }'); };
like($@, qr/^throw_code: .*js boom/, 'throw new Error');
eval { calc(throws_code => 'function() { throw "str boom"; }'); };
like($@, qr/^throws_code: .*str boom/, 'throw string');
eval { calc(syntax_code => 'function() { return ( ; }'); };
like($@, qr/^syntax_code: /, 'syntax error names the field');
eval { calc(fn_code => 'function() { return function() {}; }'); };
like($@, qr/^fn_code: /, 'returning a function fails');
is(calc(after_code => 'function() { return row.cli; }'), '89123', 'engine still works after errors');

NGCP::Panel::Utils::ProvisioningTemplates::provision_cleanup($c, $context);
NGCP::Panel::Utils::ProvisioningTemplates::provision_cleanup($c, $context);
ok(1, 'cleanup twice');

done_testing();
