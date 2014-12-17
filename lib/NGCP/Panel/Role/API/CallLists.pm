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
    my ($self, $c, $item, $owner, $form, $href_data) = @_;
    my $resource = $self->resource_from_item($c, $item, $owner, $form);

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
        exceptions => [],
    );

    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $owner, $form) = @_;
    my $sub = $owner->{subscriber};
    my $cust = $owner->{customer};
    my $resource = {};
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    );

    $resource->{call_id} = $item->call_id;

    my $intra = 0;
    if($item->source_user_id && $item->source_account_id == $item->destination_account_id) {
        $resource->{intra_customer} = JSON::true;
        $intra = 1;
    } else {
        $resource->{intra_customer} = JSON::false;
        $intra = 0;
    }
    # out by default
    $resource->{direction} = (defined $sub && $sub->uuid eq $item->destination_user_id) ?
        "in" : "out";

    my ($src_sub, $dst_sub);
    if($item->source_subscriber && $item->source_subscriber->provisioning_voip_subscriber) {
        $src_sub = $item->source_subscriber->provisioning_voip_subscriber;
    }
    if($item->destination_subscriber && $item->destination_subscriber->provisioning_voip_subscriber) {
        $dst_sub = $item->destination_subscriber->provisioning_voip_subscriber;
    }
    my ($own_normalize, $other_normalize, $own_domain, $other_domain);

    if($resource->{direction} eq "out") {
        # for pbx out calls, use extension as own cli
        if($src_sub && $src_sub->pbx_extension) {
            $resource->{own_cli} = $src_sub->pbx_extension;
        } else {
            $resource->{own_cli} = $item->source_cli;
            $own_normalize = 1;
        }
        $own_domain = $item->source_domain;

        # for intra pbx out calls, use extension as other cli
        if($intra && $dst_sub && $dst_sub->pbx_extension) {
            $resource->{other_cli} = $dst_sub->pbx_extension;
        # if there is an alias field (e.g. gpp0), use this
        } elsif($item->destination_account_id && $c->req->param('alias_field')) {
            my $alias = $item->get_column('destination_'.$c->req->param('alias_field'));
            $resource->{other_cli} = $alias // $item->destination_user_in;
            $other_normalize = 1;
        } else {
            $resource->{other_cli} = $item->destination_user_in;
            $other_normalize = 1;
        }
        $other_domain = $item->destination_domain;
    } else {
        # for pbx in calls, use extension as own cli
        if($dst_sub && $dst_sub->pbx_extension) {
            $resource->{own_cli} = $dst_sub->pbx_extension;
        } else {
            $resource->{own_cli} = $item->destination_user_in;
            $own_normalize = 1;
        }
        $own_domain = $item->destination_domain;

        # for intra pbx in calls, use extension as other cli
        if($intra && $src_sub && $src_sub->pbx_extension) {
            $resource->{other_cli} = $src_sub->pbx_extension;
        # if there is an alias field (e.g. gpp0), use this
        } elsif($item->source_account_id && $c->req->param('alias_field')) {
            my $alias = $item->get_column('source_'.$c->req->param('alias_field'));
            $resource->{other_cli} = $alias // $item->source_cli;
            $other_normalize = 1;
        } else {
            $resource->{other_cli} = $item->source_cli;
            $other_normalize = 1;
        }
        $other_domain = $item->source_domain;
    }

    if($resource->{own_cli} !~ /^\d+$/) {
        $resource->{own_cli} .= '@'.$own_domain;
    } elsif($own_normalize) {
        $resource->{own_cli} = NGCP::Panel::Utils::Subscriber::apply_rewrite(
            c => $c, subscriber => $sub // $src_sub->voip_subscriber,
            number => $resource->{own_cli}, direction => "caller_out"
        );
    }

    if($resource->{direction} eq "in" && $item->source_clir) {
        $resource->{other_cli} = undef;
    } elsif($resource->{other_cli} !~ /^\d+$/) {
        $resource->{other_cli} .= '@'.$other_domain;
    } elsif($other_normalize) {
        $resource->{other_cli} = NGCP::Panel::Utils::Subscriber::apply_rewrite(
            c => $c, subscriber => $sub // $src_sub->voip_subscriber,
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
