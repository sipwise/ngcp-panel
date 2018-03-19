package NGCP::Panel::Utils::Phonebook;
use strict;
use warnings;

use Sipwise::Base;
use English;
use NGCP::Panel::Utils::Generic qw(:all);

sub get_reseller_phonebook {
    my ($c, $reseller_id) = @_;
    my @pb;

    my $r_pb_rs = $c->model('DB')->resultset('reseller_phonebook')->search({
        reseller_id => $reseller_id,
    });

    for my $r ($r_pb_rs->all) {
        push @pb, { name => $r->name, number => $r->number };
    }

    return \@pb;
}

sub get_contract_phonebook {
    my ($c, $contract_id) = @_;
    my @pb;
    my %c_numbers;

    my $contract_rs = $c->model('DB')->resultset('contracts')->search({
        id => $contract_id,
    })->first;

    my $r_pb_rs = $c->model('DB')->resultset('reseller_phonebook')->search({
        reseller_id => $contract->contact->reseller->id,
    });

    my $c_pb_rs = $c->model('DB')->resultset('contract_phonebook')->search({
        contract_id => $contract_id,
    });

    for my $r ($c_pb_rs->all) {
        push @pb, { name => $r->name, number => $r->number };
        $c_numbers{$r->number} = $r->name;
    }

    for my $r ($r_pb_rs->all) {
        unless (exists $c_numbers{$r->number}) {
            push @pb, { name => $r->name, number => $r->number };
        }
    }

    return \@pb;
}

sub get_subscriber_phonebook {
    my ($c, $subscriber_id) = @_;
    my @pb;
    my %c_numbers;

    my $sub = $c->model('DB')->resultset('voip_subscribers')->search({
        id => $subscriber_id,
    })->first;

    my $r_pb_rs = $c->model('DB')->resultset('reseller_phonebook')->search({
        reseller_id => $sub->contract->contact->reseller->id,
    });

    my $c_pb_rs = $c->model('DB')->resultset('contract_phonebook')->search({
        contract_id => $sub->contract_id,
    });

    my $a_pb_rs = $c->model('DB')->resultset('subscriber_phonebook')->search({
        shared => 1,
        'contract.contract_id' => $sub->contract_id,
    },{
        join => { 'subscriber' => 'contract' },
    });

    my $s_pb_rs = $c->model('DB')->resultset('subscriber_phonebook')->search({
        subscriber_id => $subscriber_id,
    });

    for my $r ($s_pb_rs->all) {
        push @pb, { name => $r->name, number => $r->number };
        $c_numbers{$r->number} = $r->name;
    }

    for my $r ($c_pb_rs->all) {
        unless (exists $c_numbers{$r->number}) {
            push @pb, { name => $r->name, number => $r->number };
            $c_numbers{$r->number} = $r->name;
        }
    }

    for my $r ($a_pb_rs->all) {
        unless (exists $c_numbers{$r->number}) {
            push @pb, { name => $r->name, number => $r->number };
            $c_numbers{$r->number} = $r->name;
        }
    }

    for my $r ($r_pb_rs->all) {
        unless (exists $c_numbers{$r->number}) {
            push @pb, { name => $r->name, number => $r->number };
        }
    }

    return \@pb;
}

1;

=head1 NAME

NGCP::Panel::Utils::Phonebook

=head1 DESCRIPTION

A helper to manipulate the phonebook data

=head1 METHODS

=head2 get_reseller_phonebook

=head2 get_contract_phonebook

=head2 get_subscriber_phonebook

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
