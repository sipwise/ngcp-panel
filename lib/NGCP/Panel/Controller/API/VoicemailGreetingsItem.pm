package NGCP::Panel::Controller::API::VoicemailGreetingsItem;
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

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::VoicemailRecordings/;

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, voicemailgreeting => $item);

        $c->response->header ('Content-Disposition' => 'attachment; filename="' . $self->resource_name . '-' . $item->id . '.wav"');
        $c->response->content_type('audio/x-wav');
        $c->response->body($item->recording);
        return;
    }
    return;
}

# vim: set tabstop=4 expandtab:
