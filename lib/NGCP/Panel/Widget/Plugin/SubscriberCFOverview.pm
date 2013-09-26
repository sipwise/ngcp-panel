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


    my $prov_subscriber = $c->user;
    my $cfs = {};

    foreach my $type(qw/cfu cfna cft cfb/) {
        my $maps = $prov_subscriber->voip_cf_mappings
            ->search({ type => $type });
        $cfs->{$type} = [];
        foreach my $map($maps->all) {
            my @dset = map { { $_->get_columns } } $map->destination_set->voip_cf_destinations->search({},
                { order_by => { -asc => 'priority' }})->all;
            foreach my $d(@dset) {
                $d->{as_string} = NGCP::Panel::Utils::Subscriber::destination_as_string($d);
            }
            my @tset = ();
            if($map->time_set) {
                @tset = map { { $_->get_columns } } $map->time_set->voip_cf_periods->all;
                foreach my $t(@tset) {
                    $t->{as_string} = NGCP::Panel::Utils::Subscriber::period_as_string($t);
                }
            }
            push @{ $cfs->{$type} }, { destinations => \@dset, periods => \@tset };
        }
    }
    $c->stash(cf_destinations => $cfs);

    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        ($c->user_in_realm('subscriber') || $c->user_in_realm('subscriberadmin')) &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
