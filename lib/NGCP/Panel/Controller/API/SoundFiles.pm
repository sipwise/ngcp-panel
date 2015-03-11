package NGCP::Panel::Controller::API::SoundFiles;
use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Defines sound files for system and customer sound sets. To create or update a sound file, do a POST or PUT with Content-Type audio/x-wav and pass '.
        'the properties via query parameters, e.g. <span>/api/soundfiles/?set_id=1&amp;filename=test.wav&amp;loopplay=true&amp;handle=music_on_hold</span>',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
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
    ]},
);

with 'NGCP::Panel::Role::API::SoundFiles';

class_has('resource_name', is => 'ro', default => 'soundfiles');
class_has('dispatch_path', is => 'ro', default => '/api/soundfiles/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-soundfiles');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(HTTPMethods)],
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
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

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

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
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

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            exceptions => [ "set_id" ],
        );
        $resource->{loopplay} = ($resource->{loopplay} eq "true" || $resource->{loopplay}->is_int && $resource->{loopplay}) ? 1 : 0;


        my $set_rs = $c->model('DB')->resultset('voip_sound_sets')->search({ 
            id => $resource->{set_id},
        });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $set_rs = $set_rs->search({
                reseller_id => $c->user->reseller_id,
            });
        }
        my $set = $set_rs->first;
        unless($set) {
            $c->log->error("invalid set_id '$$resource{set_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Sound set does not exist");
            last;
        }

        my $handle_rs = $c->model('DB')->resultset('voip_sound_handles')->search({
            'me.name' => $resource->{handle},   
        });
        my $handle;
        if($set->contract_id) {
            $handle_rs = $handle_rs->search({
                'group.name' => { 'in' => [qw/pbx music_on_hold digits/] },
            },{
                join => 'group',
            });
            $handle = $handle_rs->first;
            unless($handle) {
                $c->log->error("invalid handle '$$resource{handle}', must be in group pbx or music_on_hold for a customer sound set");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Handle must be in group pbx or music_on_hold for a customer sound set");
                last;
            }
        } else {
            $handle_rs = $handle_rs->search({
                'group.name' => { 'not in' => ['pbx'] },
            },{
                join => 'group',
            });
            $handle = $handle_rs->first;
            unless($handle) {
                $c->log->error("invalid handle '$$resource{handle}', must not be in group pbx for a system sound set");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Handle must not be in group pbx for a system sound set");
                last;
            }
        }
        $resource->{handle_id} = $handle->id;

        $resource->{data} = $recording;
        if($resource->{handle} eq 'music_on_hold' && !$set->contract_id) {
            $resource->{codec} = 'PCMA';
            $resource->{filename} =~ s/\.[^.]+$/.pcma/;
        } else {
            $resource->{codec} = 'WAV';
        }
        $resource = $self->transcode_data($c, 'WAV', $resource);
        last unless($resource);
        delete $resource->{handle};

        my $item;
        try {
            $item = $c->model('DB')->resultset('voip_sound_files')->search_rs({
                    set_id => $resource->{set_id},
                    handle_id => $resource->{handle_id},
                })->first;
            if ($item) {
                $item->update($resource);
            } else {
                $item = $c->model('DB')->resultset('voip_sound_files')->create($resource);
            }
        } catch($e) {
            $c->log->error("failed to create soundfile: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create soundfile.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

# vim: set tabstop=4 expandtab:
