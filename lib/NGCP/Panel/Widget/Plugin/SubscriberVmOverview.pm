package NGCP::Panel::Widget::Plugin::SubscriberVmOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/subscriber_vm_overview.tt'
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

    my $rs = $c->model('DB')->resultset('voicemail_spool')->search({
        mailboxuser => $c->user->uuid,
        dir => { -like => '%/INBOX' },
    }, {
        order_by => { -desc => 'me.origtime' },
    })->slice(0, 9);

    $c->stash(
        vmails => $rs,
    );
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
