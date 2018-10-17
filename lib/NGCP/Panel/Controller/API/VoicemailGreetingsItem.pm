package NGCP::Panel::Controller::API::VoicemailGreetingsItem;

use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Sounds;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::VoicemailGreetings/;

__PACKAGE__->set_config({
    PUT => { 
        'ContentType' => ['multipart/form-data'],#,
        'Uploads'    => {'greetingfile' => ['audio/x-wav', 'application/octet-stream']},
    },
    GET => {
        #'application/json' is default, if no accept header was recieved.
        'ReturnContentType' => ['application/json', 'audio/x-wav', 'audio/mpeg', 'audio/ogg'],#,
    },
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PUT DELETE/];
}

sub update_item_model{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $dir = NGCP::Panel::Utils::Subscriber::get_subscriber_voicemail_directory(c => $c, subscriber => $c->stash->{checked}->{subscriber}, dir => $resource->{dir} );
    
    $item->update({
        'recording'     => ${$process_extras->{binary_ref}},
        'dir'           => $dir,
        'mailboxuser'   => $c->stash->{checked}->{subscriber}->uuid,
        'origtime'      => time(),#just to make inflate possible. Really we don't need this value
    });
    #we need to return subscriber id, so item can be used for further update
    #We can't just add field to the item object, so we need to reselect it
    $item = $self->item_by_id($c, $item->id);
    return $item;
}

sub get_item_binary_data{
    my($self, $c, $id, $item, $return_type) = @_;
    #caller waits for: $data_ref,$mime_type,$filename
    #while we will not strictly check Accepted header, if item can return only one type of the binary data
    my $extension = mime_type_to_extension($return_type);
    my $data_ref;
    if ($extension ne 'wav') {
        $data_ref = NGCP::Panel::Utils::Sounds::transcode_data(\$item->recording, 'WAV', uc($extension));
    } else {
        $data_ref = \$item->recording;
    }
    my $filename = 'voicemail_'. NGCP::Panel::Utils::Subscriber::get_subscriber_voicemail_type( dir => $item->dir ).'_'.$item->get_column('subscriber_id').'.'.$extension;
    return $data_ref, $return_type, $filename;
}

1;

# vim: set tabstop=4 expandtab:
