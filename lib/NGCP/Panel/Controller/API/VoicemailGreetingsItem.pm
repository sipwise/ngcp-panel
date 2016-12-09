package NGCP::Panel::Controller::API::VoicemailGreetingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

__PACKAGE__->set_config();

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesFilesItem NGCP::Panel::Role::API::VoicemailGreetings/;

#sub _set_config{
#    my ($self, $method) = @_;
#    $method //='';
#    if ('PUT' eq $method || 'POST' eq $method){
#        return { 'ContentType' => 'audio/x-wav' };
#    }
#    return {};
#}

#sub GET :Allow {
#    my ($self, $c, $id) = @_;
#    {
#        last unless $self->valid_id($c, $id);
#        my $item = $self->item_by_id($c, $id);
#        last unless $self->resource_exists($c, voicemailgreeting => $item);
#
#        $c->response->header ('Content-Disposition' => 'attachment; filename="' . $self->resource_name . '-' . $item->id . '.wav"');
#        $c->response->content_type('audio/x-wav');
#        $c->response->body($item->recording);
#        return;
#    }
#    return;
#}

# vim: set tabstop=4 expandtab:
