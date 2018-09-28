package NGCP::Panel::Utils::TimeSet;

use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::DateTime;

sub delete_timesets {
    my %params = @_;
    my($c, $timeset) = @params{qw/c timeset/};

    $timeset->delete();
}

sub update_timesets {
    my %params = @_;
    my($c, $timeset, $resource, $form) = @params{qw/c timeset resource form/};

    $timeset->update({
            name => $resource->{name},
            reseller_id => $resource->{reseller_id},
        })->discard_changes;
    $timeset->time_periods->delete;
    for my $t ( @{ $form->values->{times} } ) { # not taking @{$resource->{times}}, to benefit from formhandler inflation
        $timeset->create_related("time_periods", {
                %{ $t },
            });
    }
}

sub create_timesets {
    my %params = @_;
    my($c, $resource) = @params{qw/c resource/};

    my $schema = $c->model('DB');

    my $timeset = $schema->resultset('voip_time_sets')->create({
        name => $resource->{name},
        reseller_id => $resource->{reseller_id},
    });
    for my $t ( @{$resource->{times}} ) {
        $timeset->create_related("time_periods", {
            %{ $t },
        });
    }
    return $timeset;
}

sub get_timeset {
    my %params = @_;
    my($c, $timeset, $date_mysql_format) = @params{qw/c timeset date_mysql_format/};

    my $resource = { $timeset->get_inflated_columns };

    my @periods;
    for my $period ($timeset->time_periods->all) {
        my $period_infl = { $period->get_inflated_columns, };
        delete @{ $period_infl }{'time_set_id', 'id'};
        if (!$date_mysql_format) {
            foreach my $date_key (qw/start end until/) {
                if (defined $period_infl->{$date_key}) {
                    $period_infl->{$date_key} = NGCP::Panel::Utils::DateTime::from_mysql_to_js($period_infl->{$date_key});
                }
            }
        }
        for my $k (keys %{ $period_infl }) {
            delete $period_infl->{$k} unless defined $period_infl->{$k};
        }
        push @periods, $period_infl;
    }
    $resource->{times} = \@periods;
    return $resource;
}
1;

=head1 NAME

NGCP::Panel::Utils::TimeSet

=head1 DESCRIPTION

A temporary helper to manipulate resellers data

=head1 METHODS

=head2 update_timesets

Update timesets database data

=head2 create_timesets

Create timesets database data

=head2 get_timesets

Get timesets data from database to show to the user

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
