package NGCP::Panel::Controller::API::SoundFiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines sound files for system and customer sound sets. To create or update a sound file, do a POST or PUT with Content-Type audio/x-wav and pass '.
        'the properties via query parameters, e.g. <span>/api/soundfiles/?set_id=1&amp;filename=test.wav&amp;loopplay=true&amp;handle=music_on_hold</span>';
}

sub query_params {
    return [
        {
            param => 'set_id',
            description => 'Filter for sound files of a specific sound set',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'set_id' => $q };
                },
                second => sub { },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SoundFiles/;

sub resource_name{
    return 'soundfiles';
}

sub dispatch_path{
    return '/api/soundfiles/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-soundfiles';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    #$self->log_request($c);
    return 1;
}



sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $recording = $self->get_valid_raw_post_data(
            c => $c, 
            media_type => 'audio/x-wav',
        );
        last unless $recording;
        my $resource = $c->req->query_params;
        $resource->{data} = $recording;
        my $form = $self->get_form($c);
        my $item;

        my $tmp_item = $self->item_rs($c)->search_rs({
                set_id => $resource->{set_id},
                'handle.name' => $resource->{handle},
            },{
                join => 'handle',
            })->first;
        $item = $self->update_item($c, $tmp_item, undef, $resource, $form);
        last unless $item;

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
