package NGCP::Panel::Widget::Dashboard::SubscriberCFOverview;

use warnings;
use strict;

sub template {
    return 'widgets/subscriber_cf_overview.tt';
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin')
    );
    return;
}

sub _get_cf_type_descriptions {
    my ($self, $c) = @_;
    return { cfu  => $c->loc("Call Forward Unconditional"),
             cfb  => $c->loc("Call Forward Busy"),
             cft  => $c->loc("Call Forward Timeout"),
             cfna => $c->loc("Call Forward Unavailable"),
             cfs => $c->loc("Call Forward SMS"),
             cfr => $c->loc("Call Forward on Response"), };
             cfo => $c->loc("Call Forward on Overflow"), };
}

sub cfs {
    my ($self, $c) = @_;

    my $prov_subscriber = $c->user;
    my $cfs = {};
    my $descriptions = $self->_get_cf_type_descriptions($c);

    foreach my $type (qw/cfu cfna cft cfb cfs cfr cfo/) {
        my $maps = $prov_subscriber->voip_cf_mappings
            ->search({ type => $type });
        my @mappings = ();
        foreach my $map ($maps->all) {
            my @dset = map { { $_->get_columns } } $map->destination_set->voip_cf_destinations->search({},
                { order_by => { -asc => 'priority' }})->all;
            foreach my $d (@dset) {
                my $as_string = NGCP::Panel::Utils::Subscriber::destination_as_string($c, $d, $prov_subscriber);
                delete @$d{keys %$d};
                $d->{as_string} = $as_string;
            }
            my @tset = ();
            if ($map->time_set) {
                @tset = map { { $_->get_columns } } $map->time_set->voip_cf_periods->all;
                foreach my $t (@tset) {
                    my $as_string = NGCP::Panel::Utils::Subscriber::period_as_string($t);
                    delete @$t{keys %$t};
                    $t->{as_string} = $as_string;
                }
            }
            push @mappings, {
                destinations => \@dset,
                periods => \@tset,
            };
        }
        $cfs->{$type} = {
            mappings => \@mappings,
            desc => $descriptions->{$type},
        };
    }

    return $cfs;
}

1;
# vim: set tabstop=4 expandtab:
