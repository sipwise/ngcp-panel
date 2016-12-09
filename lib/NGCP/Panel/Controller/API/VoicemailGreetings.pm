package NGCP::Panel::Controller::API::VoicemailGreetings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::VoicemailGreetings/;

__PACKAGE__->set_config();

sub allowed_methods{
    return [qw/OPTIONS HEAD GET POST/];
}

sub api_description {
    return 'Defines the voicemail greetings. A GET on an item with Accept "audio/x-wav" returns the binary blob of the greeting.';
};

sub _set_config{
    my ($self, $method) = @_;
    $method //='';
    if ('POST' eq $method || 'PUT' eq $method){
        return { 
            'ContentType' => ['multipart/form-data'],#, 
            'Uploads'    => {'greetingfile' => ['audio/x-wav', 'application/octet-stream']}, 
        };
    }
    return {};
}


sub query_params {
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
                        $wheres{'domain.id'} = { -ident => 'subscriber.domain_id' };
                    }

                    my $h = 
                    return {
                        'voip_subscriber.id' => $q,
                        %wheres,
                    };
                },
                second => sub {
                    my $q = shift;
                    my $c = shift;
                    my @joins = ();
                    if( $c->config->{features}->{multidomain}) {
                        push @joins, 'domain' ;
                    }
                    return {
                        join => [{ subscriber => 'voip_subscriber' },@joins]
                    };
                },
            },
        },
    ];
};

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $rs = $self->item_rs();

    my $item = $rs->create({
        'recording'           => $resource->{greetingfile}->slurp,
        'dir'                 => $resource->{dir},
        'msgnum'              => '-1',
        'voips_subscriber.id' => $resource->{subscriber_id},
    });
    return $item;
}


1;

# vim: set tabstop=4 expandtab:
