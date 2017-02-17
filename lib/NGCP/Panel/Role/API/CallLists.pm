package NGCP::Panel::Role::API::CallLists;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use POSIX;
use DateTime::Format::Strptime;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::CallList;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Form::CallList::Subscriber;

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
                { 'source_account_id' => $c->user->account_id },
                { 'destination_account_id' => $c->user->account_id },
            ],
        });
    } else {
        my $out_rs = $item_rs->search_rs({
            source_user_id => $c->user->voip_subscriber->uuid,
        });
        my $in_rs = $item_rs->search_rs({
            destination_user_id => $c->user->voip_subscriber->uuid,
        });
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
    return NGCP::Panel::Form::CallList::Subscriber->new;
}

sub hal_from_item {
    my ($self, $c, $item, $owner, $form, $href_data) = @_;
    my $resource = $self->resource_from_item($c, $item, $owner, $form);

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d?%s", $self->dispatch_path, $item->id, $href_data)),
            # todo: customer can be in source_account_id or destination_account_id
#            Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->source_customer_id)),
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
    if($c->req->param('tz') && DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
        # valid tz is checked in the controllers' GET already, but just in case
        # it passes through via POST or something, then just ignore wrong tz
        $item->start_time->set_time_zone($c->req->param('tz'));
    }

    $resource->{start_time} = $datetime_fmt->format_datetime($item->start_time);
    $resource->{start_time} .= '.'.$item->start_time->millisecond if $item->start_time->millisecond > 0.0;
    return $resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub get_owner_data {
    my ($self, $c, $schema) = @_;

    my $ret;
    if($c->user->roles eq "admin" || $c->user->roles eq "reseller") {
        if($c->req->param('subscriber_id')) {
            my $sub = $schema->resultset('voip_subscribers')->find($c->req->param('subscriber_id'));
            unless($sub) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'subscriber_id'.");
                return;
            }
            if($c->user->roles eq "reseller" && $sub->contract->contact->reseller_id != $c->user->reseller_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'subscriber_id'.");
                return;
            }
            return {
                subscriber => $sub,
                customer => $sub->contract,
            };
        } elsif($c->req->param('customer_id')) {
            my $cust = $schema->resultset('contracts')->find($c->req->param('customer_id'));
            unless($cust && $cust->contact->reseller_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'customer_id'.");
                return;
            }
            if($c->user->roles eq "reseller" && $cust->contact->reseller_id != $c->user->reseller_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'customer_id'.");
                return;
            }
            return {
                subscriber => undef,
                customer => $cust,
            };
        } else {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Mandatory parameter 'subscriber_id' or 'customer_id' missing in request");
            return;
        }
    } elsif($c->user->roles eq "subscriberadmin") {
        if($c->req->param('subscriber_id')) {
            my $sub = $schema->resultset('voip_subscribers')->find($c->req->param('subscriber_id'));
            unless($sub) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'subscriber_id'.");
                return;
            }
            if($sub->contract_id != $c->user->account_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'subscriber_id'.");
                return;
            }
            return {
                subscriber => $sub,
                customer => $sub->contract,
            };
        } else {
            my $cust = $schema->resultset('contracts')->find($c->user->account_id);
            unless($cust && $cust->contact->reseller_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'customer_id'.");
                return;
            }
            return {
                subscriber => undef,
                customer => $cust,
            };
        }
    } else {
        return {
            subscriber => $c->user->voip_subscriber,
            customer => $c->user->voip_subscriber->contract,
        };
    }
}

1;
# vim: set tabstop=4 expandtab:
