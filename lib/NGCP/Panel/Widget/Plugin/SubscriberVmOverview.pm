package NGCP::Panel::Widget::Plugin::SubscriberVmOverview;
use Moose::Role;

use DateTime::Format::Strptime;

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
    default => 20,
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

sub _prepare_voicemails {
    my ($self, $c) = @_;

    # limited by asterisk.voicemail.maxmsg in config.yml
    my $rs = $c->model('DB')->resultset('voicemail_spool')->search({
        mailboxuser => $c->user->uuid,
        msgnum => { '>=' => 0 },
        dir => { -like => '%/INBOX' },
    });

    $c->stash(
        voicemails => $rs,
    );

}

sub voicemails_count {
    my ($self, $c) = @_;
    $self->_prepare_voicemails($c);
    return $c->stash->{voicemails}->count;
}

sub voicemails_slice {
    my ($self, $c) = @_;
    $self->_prepare_voicemails($c);
    my $sub = $c->model('DB')->resultset('voip_subscribers')->find({
                uuid => $c->user->uuid,
            });
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );
    return [ map {
                #my $voicemail= { $_->get_inflated_columns };
                #avoid loading the blob here!
                my %resource = ();
                $resource{play_uri} = $c->uri_for_action('/subscriber/play_voicemail', [$sub->id, $_->id])->as_string;
                $resource{callerid} = $_->callerid;
                $resource{origtime} = $datetime_fmt->format_datetime($_->origtime);
                $resource{duration} = $_->duration;
                \%resource;
            } $c->stash->{voicemails}->search(undef,{
                order_by => { -desc => 'me.origtime' },
            })->slice(0, 4)->all ];
}

1;
# vim: set tabstop=4 expandtab:
