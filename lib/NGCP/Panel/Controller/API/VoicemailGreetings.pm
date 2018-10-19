package NGCP::Panel::Controller::API::VoicemailGreetings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::VoicemailGreetings/;

__PACKAGE__->set_config({
    POST => { 
        'ContentType' => ['multipart/form-data'],#,
        'Uploads'    => {'greetingfile' => ['audio/x-wav', 'application/octet-stream']},
    },
});

sub allowed_methods{
    return [qw/OPTIONS HEAD GET POST/];
}

sub config_allowed_roles {
    return [qw/admin reseller subscriberadmin subscriber/];
}

sub api_description {
    return 'Defines the voicemail greetings. A GET on an item with Accept "audio/x-wav" returns the binary blob of the greeting.';
};

sub query_params {
    my ($self) = @_;
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for registrations of a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    my $c = shift;
                    my %wheres = ();
                    if( $c->config->{features}->{multidomain}) {
                        $wheres{'domain.id'} = { -ident => 'voip_subscriber.domain_id' };
                    }
                    return {
                        'voip_subscriber.id' => $q,
                        %wheres,
                    };
                },
                second => sub {
                    my $q = shift;
                    my $c = shift;
                    my $subscriber_join = 'voip_subscriber';
                    if( $c->config->{features}->{multidomain}) {
                        $subscriber_join = { 'voip_subscriber' => 'domain' };
                    }
                    return {
                        join => [{ 'mailboxuser' => { 'provisioning_voip_subscriber' => $subscriber_join }}]
                    };
                },
            },
        },
        {
            param => 'type',
            description => 'Filter for the greeting type',
            query => {
                first => sub {
                    my $q = shift;
                    return {
                        'me.dir' => { like => '/var/spool/asterisk/voicemail/%/'.$q },
                    };
                },
                second => sub {},
            },
        },
        {
            param       => 'format',
            description => 'Output format of the voicemail greeting file, supported: '.join(', ',@{$self->supported_mime_types_extensions}),
            type        => 'mime_type',
        },
    ];
};

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;
    my $dir = NGCP::Panel::Utils::Subscriber::get_subscriber_voicemail_directory( c => $c, subscriber => $c->stash->{checked}->{subscriber}, dir => $resource->{dir} );
    my $item = $c->stash->{checked}->{voicemail_subscriber}->voicemail_spools->create({
        'recording'      => ${$process_extras->{binary_ref}},
        'dir'            => $dir,
        'origtime'       => time(),#just to make inflate possible. Really we don't need this value
        'mailboxcontext' => 'default',
        'msgnum'         => '-1',
    });
    #we need to return subscriber id, so item can be used for further update
    #We can't just add field to the item object, so we need to reselect it
    $item = $self->item_by_id($c, $item->id);
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
