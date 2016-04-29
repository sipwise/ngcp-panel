package NGCP::Panel::Widget::Dashboard::SubscriberRegisterOverview;
use Moo;

has 'template' => (
    is  => 'ro',
    default => 'widgets/subscriber_reg_overview.tt'
);

sub handle {
    my ($self, $c) = @_;

    unless ($c->stash->{subscriber}) {
        $c->stash(
            subscriber => $c->model('DB')->resultset('voip_subscribers')->find({
                uuid => $c->user->uuid,
            }),
        );
    }

    return;
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin')
    );
    return;
}

sub _prepare_registrations {
    my ($self, $c) = @_;

    my $rs = $c->model('DB')->resultset('location')->search({
        username => $c->user->username,
    });
    if($c->config->{features}->{multidomain}) {
        $rs = $rs->search({
            domain => $c->user->domain->domain,
        });
    }

    $c->stash(registrations => $rs);

}

sub registrations_slice {
    my ($self, $c) = @_;
    $self->_prepare_registrations($c);
    return [ map {
                my $registration = { $_->get_inflated_columns };
                my %resource = ();
                $resource{user_agent} = $registration->{user_agent};
                \%resource;
            } $c->stash->{registrations}->slice(0,4)->all ];
}

sub registrations_count {
    my ($self, $c) = @_;
    $self->_prepare_registrations($c);
    return $c->stash->{registrations}->count;
}

1;
# vim: set tabstop=4 expandtab:
