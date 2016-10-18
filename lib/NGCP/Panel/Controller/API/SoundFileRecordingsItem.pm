package NGCP::Panel::Controller::API::SoundFileRecordingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SoundFiles/;

sub resource_name{
    return 'soundfilerecordings';
}
sub dispatch_path{
    return '/api/soundfilerecordings/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-soundfilerecordings';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin/],
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);



sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, soundfilerecording => $item);
        my $resource = $self->resource_from_item($c, $item);

        $resource->{data} = $item->data;
        if($item->codec eq "PCMA") {
            $resource->{codec} = 'WAV';
            $resource = $self->transcode_data($c, $item->codec, $resource);
            last unless($resource);
        }

        $c->response->header ('Content-Disposition' => 'attachment; filename="' . $resource->{filename} . '"');
        $c->response->content_type('audio/x-wav');
        $c->response->body($resource->{data});
        return;
    }
    return;
}





sub end : Private {
    my ($self, $c) = @_;

    #$self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
