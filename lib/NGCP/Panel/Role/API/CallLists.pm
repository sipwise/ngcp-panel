package NGCP::Panel::Role::API::CallLists;
use Moose::Role;
use Sipwise::Base;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use POSIX;
use DateTime::Format::Strptime;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Form::CallList::Subscriber;

sub item_rs {
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
        $item_rs = $item_rs->search({ 
            -or => [
                { 'source_subscriber.id' => $c->user->voip_subscriber->id },
                { 'destination_subscriber.id' => $c->user->voip_subscriber->id },
            ],
        },{
            join => ['source_subscriber', 'destination_subscriber'],
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::CallList::Subscriber->new;
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::CallList::Subscriber->new;
    } else {
        return NGCP::Panel::Form::CallList::Subscriber->new;
    }
}

sub hal_from_item {
    my ($self, $c, $item, $sub, $form) = @_;
    my $resource = $self->resource_from_item($c, $item, $sub, $form);

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
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
        exceptions => [],
    );

    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $sub, $form) = @_;
    my $resource = {};
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    );

    $resource->{direction} = $sub->uuid eq $item->source_user_id ?
        "out" : "in";
    $resource->{other_cli} = $resource->{direction} eq "out" ?
        $item->destination_user_in : $item->source_cli;
    if($resource->{direction} eq "in" && $item->source_clir) {
        $resource->{other_cli} = undef;
    } elsif($resource->{other_cli} !~ /^\d+$/) {
        $resource->{other_cli} .= '@'.$item->destination_domain_in;
    } else {
        $resource->{other_cli} = NGCP::Panel::Utils::Subscriber::apply_rewrite(
            c => $c, subscriber => $sub,
            number => $resource->{other_cli}, direction => "caller_out"
        );
    }
    $resource->{status} = $item->call_status;
    $resource->{type} = $item->call_type;

    $resource->{start_time} = $datetime_fmt->format_datetime($item->start_time);
    $resource->{duration} = NGCP::Panel::Utils::DateTime::sec_to_hms(ceil($item->duration));
    $resource->{customer_cost} = $resource->{direction} eq "out" ?
        $item->source_customer_cost : $item->destination_customer_cost;
    $resource->{customer_free_time} = $resource->{direction} eq "out" ?
        $item->source_customer_free_time : 0;

    return $resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
