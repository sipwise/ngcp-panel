package NGCP::Panel::Role::API::CallLists;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use POSIX;
use DateTime::Format::Strptime;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::CallList;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::CallList qw();
use NGCP::Panel::Utils::API::Calllist qw();

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('cdr');

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

sub hal_from_item {
    my ($self, $c, $item, $owner, $form, $href_data) = @_;
    my $resource = $self->resource_from_item($c, $item, $owner, $form);

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d?%s", $self->dispatch_path, $item->id, $href_data)),
            # todo: customer can be in source_account_id or destination_account_id
#            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->source_customer_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
        exceptions => [qw/call_id/],
    );

    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $owner, $form) = @_;

    my $resource = NGCP::Panel::Utils::CallList::process_cdr_item($c, $item, $owner);

    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );

    my $start_time = NGCP::Panel::Utils::API::Calllist::apply_owner_timezone($self,$c,$item->start_time,$owner);
    $resource->{start_time} = $datetime_fmt->format_datetime($start_time);
    $resource->{start_time} .= '.'.sprintf("%03d",$start_time->millisecond) if $start_time->millisecond > 0.0;

    my $init_time = NGCP::Panel::Utils::API::Calllist::apply_owner_timezone($self,$c,$item->init_time,$owner);
    $resource->{init_time} = $datetime_fmt->format_datetime($init_time);
    $resource->{init_time} .= '.'.sprintf("%03d",$init_time->millisecond) if $init_time->millisecond > 0.0;
    return $resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
