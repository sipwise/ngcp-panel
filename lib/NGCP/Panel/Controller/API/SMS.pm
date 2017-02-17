package NGCP::Panel::Controller::API::SMS;

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SMS/;

use HTTP::Status qw(:constants);


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

    my $error_msg = "";

    NGCP::Panel::Utils::SMS::send_sms(
            c => $c,
            caller => $resource->{caller},
            callee => $resource->{callee},
            text => $resource->{text},
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
            $error_msg ? (status => $error_msg) : (),
        });
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
