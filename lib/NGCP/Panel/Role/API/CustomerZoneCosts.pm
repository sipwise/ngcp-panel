package NGCP::Panel::Role::API::CustomerZoneCosts;
use Moose::Role;
use Sipwise::Base;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use Data::HAL::Link qw();
use Data::HAL qw();
use DateTime::Format::Strptime;
use HTTP::Status qw(:constants);
use JSON::Types;
use TryCatch;
use NGCP::Panel::Utils::Contract;

has 'datetime_format' => (
    is => 'rw',
    default => sub { DateTime::Format::Strptime->new(pattern => '%Y-%m-%dT%H%M%S',
            time_zone => DateTime::TimeZone->new(name => 'local'),
            on_error => 'undef',
        )},
);

sub get_form {
    my ($self, $c) = @_;
    return '';
}

sub hal_from_item {
    my ($self, $c, $item) = @_;
    my $form;
    my $type = 'customerzonecosts';

    my $query_string = $self->query_param_string($c);

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("%s?%s", $self->dispatch_path, $query_string)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d?%s", $self->dispatch_path, $item->id, $query_string)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%d?%s", $type, $item->id, $query_string)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->resource_from_item($c, $item);
    return unless $resource;
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item) = @_;

    my %resource;

    my ($stime, $etime, $subscriber_id) = $self->get_query_params($c);
    my $subscriber_uuid;
    if ($subscriber_id) {
        my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find({ id => $subscriber_id });
        unless ($subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber_id. Subscriber not found.");
            $c->log->debug("invalid subscriber");
            return;
        }
        $subscriber_uuid = $subscriber->uuid;
        $c->log->debug("filtering by subscriber $subscriber_uuid");
    }

    my $zonecalls = NGCP::Panel::Utils::Contract::get_contract_zonesfees(
        c => $c,
        contract_id => $item->id,
        stime => $stime,
        etime => $etime,
        subscriber_uuid => $subscriber_uuid,
        in => 1,
        out => 1,
        group_by_detail => 0,
    );

    $resource{customer_id} = int($item->id);
    $resource{zones} = $zonecalls;

    return \%resource;
}

sub get_query_params {
    my ($self, $c) = @_;

    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1)->subtract(seconds => 1);

    my $format = $self->datetime_format;

    if ( $c->request->query_params->{start} ) {
        $stime = $format->parse_datetime( $c->request->query_params->{start} );
    }
    if ( $c->request->query_params->{end} ) {
        $etime = $format->parse_datetime( $c->request->query_params->{end} );
    }
    unless ($stime && $etime) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid datetime format in query parameters.");
        return;
    }

    my $subscriber_id = $c->request->query_params->{subscriber_id};

    return ($stime, $etime, $subscriber_id);
}

sub query_param_string {
    my ($self, $c) = @_;

    my $format = $self->datetime_format;

    my ($stime, $etime, $subscriber_id) = $self->get_query_params($c);
    return '' unless ($stime && $etime);
    my $query_string = sprintf("start=%s&end=%s",
        $format->format_datetime($stime),
        $format->format_datetime($etime) );

    $query_string = $query_string . "&subscriber_id=$subscriber_id" if $subscriber_id;

    return $query_string;
}

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c);
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
