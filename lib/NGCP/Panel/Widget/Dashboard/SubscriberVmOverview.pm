package NGCP::Panel::Widget::Dashboard::SubscriberVmOverview;

use warnings;
use strict;

use NGCP::Panel::Utils::DateTime;
use DateTime::Format::Strptime;

sub template {
    return 'widgets/subscriber_vm_overview.tt';
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin')
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
                $resource{duration} = NGCP::Panel::Utils::DateTime::sec_to_hms($c,$_->duration);
                \%resource;
            } $c->stash->{voicemails}->search(undef,{
                order_by => { -desc => 'me.origtime' },
            })->slice(0, 4)->all ];
}

1;
# vim: set tabstop=4 expandtab:
