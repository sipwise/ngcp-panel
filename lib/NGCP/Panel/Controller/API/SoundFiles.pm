package NGCP::Panel::Controller::API::SoundFiles;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

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

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);

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
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item ($items->all) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
        }
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

        my $hal = NGCP::Panel::Utils::DataHal->new(
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
