package NGCP::Panel::Widget::Dashboard::SubscriberCallsOverview;

use warnings;
use strict;

use NGCP::Panel::Utils::DateTime;
use DateTime::Format::Strptime;
use URI::Escape;
use NGCP::Panel::Utils::CallList qw();

sub template {
    return 'widgets/subscriber_calls_overview.tt';
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin')
    );
    return;
}

sub _prepare_calls {
    my ($self, $c) = @_;

    my $out_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$c->model('DB')->resultset('cdr')->search_rs({
        source_user_id => $c->user->uuid,
    }),NGCP::Panel::Utils::CallList::SUPPRESS_OUT);
    my $in_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$c->model('DB')->resultset('cdr')->search_rs({
        destination_user_id => $c->user->uuid,
    }),NGCP::Panel::Utils::CallList::SUPPRESS_IN);
    my $calls_rs = $out_rs->union_all($in_rs);

    $c->stash(calls_rs => $calls_rs);

}

sub calls_count {
    my ($self, $c) = @_;
    $self->_prepare_calls($c);

    my $stime = NGCP::Panel::Utils::DateTime::current_local->subtract(hours => 24);

    $c->stash->{calls_rs}->search({
            start_time => { '>=' => $stime->epoch }
        })->count;
}

sub calls_slice {
    my ($self, $c) = @_;
    $self->_prepare_calls($c);
    my $sub = $c->user->voip_subscriber;
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );
    return [ map {
                my $call = { $_->get_inflated_columns };
                my %resource = ();
                $resource{destination_user_in} = URI::Escape::uri_unescape(
                    NGCP::Panel::Utils::Subscriber::apply_rewrite(
                        c => $c, subscriber => $sub, number => $call->{destination_user_in}, direction => 'caller_out'
                    )
                );
                $resource{source_cli} = ($call->{clir} ? $c->loc('anonymous') : URI::Escape::uri_unescape(
                    NGCP::Panel::Utils::Subscriber::apply_rewrite(
                        c => $c, subscriber => $sub, number => $call->{source_cli}, direction => 'caller_out'
                    )
                ));
                $resource{call_status} = $call->{call_status};
                $resource{source_user_id} = $call->{source_user_id};
                $resource{start_time} = $datetime_fmt->format_datetime($call->{start_time});
                $resource{duration} = NGCP::Panel::Utils::DateTime::sec_to_hms($c,$call->{duration});
                NGCP::Panel::Utils::CallList::suppress_cdr_fields($c,\%resource,$_);
            } $c->stash->{calls_rs}->search(undef, {
                    order_by => { -desc => 'me.start_time' },
            })->slice(0, 4)->all ];
}

1;
# vim: set tabstop=4 expandtab:
