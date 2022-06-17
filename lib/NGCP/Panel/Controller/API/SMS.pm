package NGCP::Panel::Controller::API::SMS;

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SMS/;

use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Utf8;
use NGCP::Panel::Utils::SMS;
use NGCP::Panel::Utils::Preferences;
use UUID;


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
    my $test_mode = $c->request->params->{test_mode} // '';

    my ($uuid, $session_id);
    UUID::generate($uuid);
    UUID::unparse($uuid, $session_id);

    my $session = {
        caller => $resource->{caller},
        callee => $resource->{callee},
        status => 'ok',
        reason => 'accepted',
        parts  => [],
        sid    => $session_id,
        rpc    => $parts,
        coding => undef,
    };

    my $smsc_peer = 'default';
    try {
        $session->{parts} = NGCP::Panel::Utils::SMS::get_number_of_parts($resource->{text});

        $session->{coding} = NGCP::Panel::Utils::SMS::get_coding($resource->{text});

        my $smsc_peer_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
            c => $c, attribute => 'smsc_peer',
            prov_domain => $subscriber->domain,
        );
        if ($smsc_peer_rs && $smsc_peer_rs->first && $smsc_peer_rs->first->value) {
            $smsc_peer = $smsc_peer_rs->first->value;
        }

        if ( 'dont_send_sms' ne $test_mode ) {

            NGCP::Panel::Utils::SMS::send_sms(
                    c => $c,
                    smsc_peer => $smsc_peer,
                    caller => $resource->{caller},
                    callee => $resource->{callee},
                    text => $resource->{text},
                    coding => $session->{coding},
                    err_code => sub {
                        $session->{reason} = shift;
                        $session->{status} = 'failed';
                    }
            );

        }

        if ($session->{status} eq 'failed') {
            die $session->{reason}."\n";
        }
    } catch($e) {
        $c->log->error($e);
        if ($session && $session->{reason} eq 'insufficient credit') {
            $self->error($c, HTTP_PAYMENT_REQUIRED, "Not enough credit to send the sms");
        } else {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR,
                "An internal error has occurred when sending the sms, please contact the platform administrator or try again later");
        }
    }

    # TODO: agranig: we need to return an item here, otherwise it fails
    #if($c->user->roles eq "admin" || $c->user->roles eq "reseller") {
    #    if($c->req->params->{skip_journal} eq "true") {
    #        return;
    #    }
    #}

    my $item = NGCP::Panel::Utils::SMS::add_journal_record(
        c => $c,
        prov_subscriber => $subscriber,
        direction => 'out',
        caller => $resource->{caller},
        callee => $resource->{callee},
        text   => $resource->{text},
        coding => $session->{coding},
        status => $session->{status} // '',
        reason => $session->{reason} // '',
        smsc_peer => $smsc_peer,
    );

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
