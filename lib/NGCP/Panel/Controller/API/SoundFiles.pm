package NGCP::Panel::Controller::API::SoundFiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use JSON;
use Encode qw (encode_utf8);


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

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $response = HTTP::Response->new(HTTP_OK, undef, 
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my ($recording, $resource);
        if ( $c->req->content_type eq 'multipart/form-data' ) {
            my $upload = $c->req->upload('soundfile');
            if ($upload) {
                $recording = eval { $upload->slurp };
            }
            last unless $recording;
            my $json_raw = encode_utf8($c->req->params->{json});
            $resource = JSON::from_json($json_raw, { utf8 => 0 });
        } else {
            my $ctype = $self->get_content_type($c);
            if ($ctype && $ctype eq 'application/json') {
                $resource = $self->get_valid_post_data(
                    c => $c,
                    media_type => 'application/json',
                );
                last unless $resource;
            } else {
                $recording = $self->get_valid_raw_post_data(
                    c => $c,
                    media_type => ['application/json', 'audio/x-wav', 'audio/mpeg', 'audio/ogg'],
                );
                last unless $recording;
                $resource = $c->req->query_params;
            }
        }
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
