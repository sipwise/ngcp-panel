package NGCP::Panel::Controller::API::Faxes;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Faxes/;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::API::Subscribers;
use NGCP::Panel::Utils::Fax;
use Encode qw( encode_utf8 );

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    dont_validate_hal => 1,
    no_item_created   => 1,
    backward_allow_empty_upload => 1,
    POST => {
        'ContentType' => ['multipart/form-data','application/json'],
        'Uploads'     => [qw/faxfile/],
    },
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines the meta information like duration, sender etc for fax recordings. The actual recordings can be fetched via the <a href="#faxrecordings">FaxRecordings</a> relation. NOTE: There is no Location header in the POST method response, as creation is asynchronous.';
};

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for faxes belonging to a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    # join is already done in get_item_rs
                    { 'voip_subscriber.id' => $q };
                },
                second => sub { },
            },
        },
        {
            param => 'time_from',
            description => 'Filter for faxes performed after or at the given time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    return { 'me.time' => { '>=' => $dt->epoch  } };
                },
                second => sub { },
            },
        },
        {
            param => 'time_to',
            description => 'Filter for faxes performed before or at the given time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    return { 'me.time' => { '<=' => $dt->epoch  } };
                },
                second => sub { },
            },
        }, 
        {
            param => 'sid',
            description => 'Filter for a fax with the specific session id',
            query_type => 'string_eq',
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    #here a little duplication of work from Entities post method. 
    #This logic saved from old faxes api
    #1) I'm not sure that we always want utf8 json; 
    #2) to prepare resource properly as NGCP::Panel::Utils::Fax::send_fax waits it
    #TODO: clarify if utf8 jason is OK always - make it in the API::get_valid_data and remove 5 lines below.
    my $json_utf8 = encode_utf8($c->req->param('json'));
    last unless $self->require_wellformed_json($c, 'application/json', $json_utf8 );
    my $resource = JSON::from_json($json_utf8, { utf8 => 0 });
    $resource->{faxfile} = $self->get_upload($c, 'faxfile');
    $c->log->debug("upload received");

    if (!$c->config->{features}->{faxserver}) {
        $c->log->error("faxserver feature is not active.");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Faxserver feature is not active.");
        return;
    }

    my $billing_subscriber = NGCP::Panel::Utils::API::Subscribers::get_active_subscriber($self, $c, $resource->{subscriber_id});
    unless($billing_subscriber) {
        $c->log->error("invalid subscriber id $$resource{subscriber_id} for fax send");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Fax subscriber not found.");
        return;
    }
    my $prov_subscriber = $billing_subscriber->provisioning_voip_subscriber;
    return unless $prov_subscriber;
    my $faxpref = $prov_subscriber->voip_fax_preference;
    unless ($faxpref && $faxpref->active){
        $c->log->error("invalid subscriber fax preferences");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid  subscriber fax preferences");
        return;
    }
    try {
        $c->log->debug("contacting fax server");
        my $output = NGCP::Panel::Utils::Fax::send_fax(
            c => $c,
            subscriber => $billing_subscriber,
            destination => $form->values->{destination},
            upload => $form->values->{faxfile},
            data => $form->values->{data},
        );
        $c->log->debug("faxserver output:\n");
        $c->log->debug($output);
    } catch($e) {
        $c->log->error("failed to send fax: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
        return;
    };
    return;
}

1;

# vim: set tabstop=4 expandtab:
