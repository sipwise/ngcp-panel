package NGCP::Panel::Controller::API::VoicemailGreetingsItem;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::VoicemailGreetings/;

__PACKAGE__->set_config();

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PUT DELETE/];
}

sub _set_config{
    my ($self, $method) = @_;
    $method //='';
    #todo: cpommon parts can be moved to the "Role" parent
    if ('POST' eq $method || 'PUT' eq $method){
        return {
            'ContentType' => ['multipart/form-data'],#,
            'Uploads'     => {'greetingfile' => ['audio/x-wav', 'application/octet-stream']},
            #TODO: check requested mimetype against provided data
            #'Accepted'    => {'audio/x-wav' => [{'recording' => 'voicemail_greeting_[%dir%]_[%subscriber_id%]'}],
        };
    }
    return {};
}

sub update_item_model{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $dir = NGCP::Panel::Utils::Subscriber::get_subscriber_voicemail_directory(c => $c, subscriber => $c->stash->{checked}->{subscriber}, dir => $resource->{dir} );
    
    $item->update({
        'recording'     => ${$process_extras->{binary_ref}},
        'dir'           => $dir,
        'subscriber_id' => 'subscriber_id',
        'origtime'      => time(),#just to make inflate possible. Really we don't need this value
    });
    #we need to return subscriber id, so item can be used for further update
    #We can't just add field to the item object, so we need to reselect it
    $item = $self->item_by_id($c, $item->id);
    return $item;
}

sub get_item_binary_data{
    my($self, $c, $id, $item) = @_;
    #caller waits for: $data_ref,$mime_type,$filename
    #while we will not strictly check Accepted header, if item can return only one type of the binary data
    return \$item->recording, 'audio/x-wav', 'voicemail_'. NGCP::Panel::Utils::Subscriber::get_subscriber_voicemail_type( dir => $item->dir ).'_'.$item->get_column('subscriber_id').'.wav',
}

# vim: set tabstop=4 expandtab:
