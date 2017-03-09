package NGCP::Panel::Controller::API::SMS;

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SMS/;

use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Utf8;
use NGCP::Panel::Utils::SMS;


__PACKAGE__->set_config();

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Shows a journal of sent and received messages. New messages can be sent by issuing a POST request to the api collection.';
}

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for messages belonging to a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'voip_subscriber.id' => $q };
                },
                second => sub {
                    return { join => {provisioning_voip_subscriber => 'voip_subscriber'}};
                },
            },
        },
        {
            param => 'customer_id',
            description => 'Filter for messages belonging to a specific customer',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'contract.id' => $q };
                },
                second => sub {
                    return { join => {provisioning_voip_subscriber => { 'voip_subscriber' => 'contract' } }};
                },
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for messages belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'contact.id' => $q };
                },
                second => sub {
                    return { join => {provisioning_voip_subscriber => { 'voip_subscriber' => { 'contract' => 'contact' } } }};
                },
            },
        },
        {
            param => 'time_ge',
            description => 'Filter for messages sent later or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.time' => { '>=' => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'time_le',
            description => 'Filter for messages sent earlier or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    $q .= ' 23:59:59' if($q =~ /^\d{4}\-\d{2}\-\d{2}$/);
                    { "me.time" => { '<=' => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'direction',
            description => 'Filter for messages sent ("out"), received ("in") or forwarded ("forward").',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q eq "out" || $q eq "in" || $q eq "forward") {
                        return { "me.direction" => $q };
                    } else {
                        return {},
                    }
                },
                second => sub {},
            },
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $subscriber = $c->model('DB')->resultset('provisioning_voip_subscribers')->find({
            id => $resource->{subscriber_id},
        });
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber");
        return;
    }
    unless($subscriber->voip_subscriber->status eq 'active') {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber is not active");
        return;
    }

    my $parts = NGCP::Panel::Utils::SMS::get_number_of_parts($resource->{text});
    try {
        unless(NGCP::Panel::Utils::SMS::perform_prepaid_billing(c => $c,
            prov_subscriber => $subscriber,
            parts => $parts,
            caller => $resource->{caller},
            callee => $resource->{callee}
        )) {
            $self->error($c, HTTP_PAYMENT_REQUIRED, "Not enough credit to send sms");
            return;
        }
    } catch($e) {
        $c->log->error("Failed to determine credit: $e");
        $self->error($c, HTTP_PAYMENT_REQUIRED, "Failed to determine credit");
        return;
    }

    my $error_msg = "";
    my $coding = NGCP::Panel::Utils::SMS::get_coding($resource->{text});
    NGCP::Panel::Utils::SMS::send_sms(
            c => $c,
            caller => $resource->{caller},
            callee => $resource->{callee},
            text => $resource->{text},
            coding => $coding,
            err_code => sub {$error_msg = shift;},
        );

    # TODO: agranig: we need to return an item here, otherwise it fails
    #if($c->user->roles eq "admin" || $c->user->roles eq "reseller") {
    #    if($c->req->params->{skip_journal} eq "true") {
    #        return;
    #    }
    #}

    my $rs = $self->item_rs($c);
    my $item = $rs->create({
            subscriber_id => $resource->{subscriber_id},
            direction => 'out',
            caller => $resource->{caller},
            callee => $resource->{callee},
            text => $resource->{text},
            coding => $coding,
            $error_msg ? (status => $error_msg) : (),
        });
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
