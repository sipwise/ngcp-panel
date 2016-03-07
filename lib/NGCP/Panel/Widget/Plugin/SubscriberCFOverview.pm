package NGCP::Panel::Widget::Plugin::SubscriberCFOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/subscriber_cf_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 30,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    unless ($c->stash->{subscriber}) {
        $c->stash(
            subscriber => $c->model('DB')->resultset('voip_subscribers')->find({
                uuid => $c->user->uuid,
            }),
        );
    }

    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

sub _get_cf_type_descriptions {
    my ($self, $c) = @_;
    return { cfu  => $c->loc("Call Forward Unconditional"),
             cfb  => $c->loc("Call Forward Busy"),
             cft  => $c->loc("Call Forward Timeout"),
             cfna => $c->loc("Call Forward Unavailable") };
}

sub cfs {
    my ($self, $c) = @_;

    my $prov_subscriber = $c->user;
    my $cfs = {};
    my $descriptions = $self->_get_cf_type_descriptions($c);

    foreach my $type (qw/cfu cfna cft cfb/) {
        my $maps = $prov_subscriber->voip_cf_mappings
            ->search({ type => $type });
        my @mappings = ();
        foreach my $map ($maps->all) {
            my @dset = map { { $_->get_columns } } $map->destination_set->voip_cf_destinations->search({},
                { order_by => { -asc => 'priority' }})->all;
            foreach my $d (@dset) {
                my $as_string = NGCP::Panel::Utils::Subscriber::destination_as_string($c, $d);
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
