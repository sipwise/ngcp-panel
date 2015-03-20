#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use NGCP::Panel::Form::SubscriberCFSimple;

my $configs = [
    {
        works => 1,
        config => {
            destination => {
                destination => 'uri',
                uri => { destination => 'sip:foo@bar.com' },
            },
        },
    },
    {
        works => 1,
        config => {
            destination => {
                destination => 'uri',
                uri => { destination => 'foo@bar.com' },
            },
        },
    },
    {
        works => 1,
        config => {
            destination => {
                destination => 'uri',
                uri => { destination => 'alice@10.0.0.1' },
            },
        },
    },
    {
        works => 1,
        config => {
            destination => {
                destination => 'uri',
                uri => { destination => '12345@a' }, # we set a domain here, because on tests it cannot be automatically deduced from stash
            },
        },
    },
    {
        works => 1,
        config => {
            destination => {
                destination => 'uri',
                uri => { destination => '+12345@a' },
            },
        },
    },
    {
        works => 0,
        config => {
            destination => {
                destination => 'uri',
                uri => { destination => '12345[678]@a' },
            },
        },
    },
    {
        works => 0,
        config => {
            destination => {
                destination => 'uri',
                uri => { destination => '+49(0)123456789@a' },
            },
        },
    },
];

for my $conf (@{$configs}) {
    my $form = NGCP::Panel::Form::SubscriberCFSimple->new;
    $form->process(
        posted => 1,
        params => $conf->{config},
    );
    my $uri = $form->value->{destination}{uri}{destination};
    if ($conf->{works}) {
        ok($form->validated, "Should validate: $uri");
    } else {
        ok(!$form->validated, "Should not validate: $uri");
    }
}

done_testing();
