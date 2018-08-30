package NGCP::Panel::Role::API::CallLists;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use HTTP::Status qw(:constants);
use POSIX;
use DateTime::Format::Strptime;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::CallList;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::CallList qw();

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('cdr')->search_rs(
        undef,
        {
            join => 'cdr_mos_data',
            '+select' => [qw/cdr_mos_data.mos_average cdr_mos_data.mos_average_packetloss cdr_mos_data.mos_average_jitter cdr_mos_data.mos_average_roundtrip/],
            '+as' => [qw/mos_average mos_average_packetloss mos_average_jitter mos_average_roundtrip/],
         }
    );

    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            -or => [
                { source_provider_id => $c->user->reseller->contract_id },
                { destination_provider_id => $c->user->reseller->contract_id },
            ],
        });
    } elsif($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            -or => [
                { source_account_id => $c->user->account_id },
                { destination_account_id => $c->user->account_id },
            ],
        });
        if (not exists $c->req->query_params->{subscriber_id}) {
            $item_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$item_rs,NGCP::Panel::Utils::CallList::SUPPRESS_INOUT);
        }
    } else {
        my $out_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$item_rs->search_rs({
            source_user_id => $c->user->voip_subscriber->uuid,
        }),NGCP::Panel::Utils::CallList::SUPPRESS_OUT);
        my $in_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$item_rs->search_rs({
            destination_user_id => $c->user->voip_subscriber->uuid,
            source_user_id => { '!=' => $c->user->voip_subscriber->uuid },
        }),NGCP::Panel::Utils::CallList::SUPPRESS_IN);
        $item_rs = $out_rs->union_all($in_rs);
    }

    $item_rs = $item_rs->search({
        -not => [
            { 'destination_domain_in' => 'vsc.local' },
        ],
    });

    return $item_rs;

}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::CallList::Subscriber", $c);
}

sub resource_from_item {
    my ($self, $c, $item, $owner, $form) = @_;

    my $resource = NGCP::Panel::Utils::CallList::process_cdr_item($c, $item, $owner);

    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );

    if($c->req->param('tz') && DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
        # valid tz is checked in the controllers' GET already, but just in case
        # it passes through via POST or something, then just ignore wrong tz
        $item->start_time->set_time_zone($c->req->param('tz'));
        $item->init_time->set_time_zone($c->req->param('tz'));
    }

    $resource->{start_time} = $datetime_fmt->format_datetime($item->start_time);
    $resource->{start_time} .= '.'.$item->start_time->millisecond if $item->start_time->millisecond > 0.0;
    $resource->{init_time} = $datetime_fmt->format_datetime($item->init_time);
    $resource->{init_time} .= '.'.$item->init_time->millisecond if $item->init_time->millisecond > 0.0;

    return $resource;
}

sub get_mandatory_params {
    my ($self, $c, $href_type, $item, $resource, $params) = @_;
    my $owner = $c->stash->{owner};
    return $owner->{subscriber} 
        ? { subscriber_id => $owner->{subscriber}->id }
        : { customer_id => $owner->{customer}->id };

}

1;
# vim: set tabstop=4 expandtab:
