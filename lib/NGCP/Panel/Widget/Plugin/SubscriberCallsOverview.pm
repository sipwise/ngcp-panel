package NGCP::Panel::Widget::Plugin::SubscriberCallsOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/subscriber_calls_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 10,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    my $out_rs = $c->model('DB')->resultset('cdr')->search({
        source_user_id => $c->user->uuid,
    });
    my $in_rs = $c->model('DB')->resultset('cdr')->search({
        destination_user_id => $c->user->uuid,
    });
    my $calls_rs = $out_rs->union_all($in_rs)->search(undef, {
         order_by => { -desc => 'me.start_time' },
    })->slice(0, 4);

    my $sub = $c->user->voip_subscriber;
    my $calls = [ map {
                my $call = { $_->get_inflated_columns };
                $call->{destination_user_in} = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                    c => $c, subscriber => $sub, number => $call->{destination_user_in}, direction => 'caller_out'
                );
                $call->{source_cli} = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                    c => $c, subscriber => $sub, number => $call->{source_cli}, direction => 'caller_out'
                );
                $call;
            } $calls_rs->all ];
    $c->stash(calls => $calls);
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

1;
# vim: set tabstop=4 expandtab:
