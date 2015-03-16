package NGCP::Panel::Utils::Journal;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;
use NGCP::Panel::Utils::DateTime;
use JSON;
use HTTP::Status qw(:constants);
use TryCatch;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use Scalar::Util 'blessed';
use Storable;
use IO::Compress::Deflate qw($DeflateError);
use IO::Uncompress::Inflate qw(); 

use constant CREATE_JOURNAL_OP => 'create';
use constant UPDATE_JOURNAL_OP => 'update';
use constant DELETE_JOURNAL_OP => 'delete';

use constant API_JOURNAL_RESOURCE_NAME => 'journal';

use constant CONTENT_JSON_FORMAT => 'json';
use constant CONTENT_STORABLE_FORMAT => 'storable';
use constant CONTENT_JSON_DEFLATE_FORMAT => 'json_deflate';

use constant CONTENT_DEFAULT_FORMAT => CONTENT_JSON_FORMAT;

sub add_journal_record_hal {
    my ($controller,$c,$operation,@args) = @_;
    my $arg = $args[0];
    my @hal_from_item = ();
    my $params;
    if (ref $arg eq 'HASH') {
        $params = $arg;
        my $h = (defined $params->{hal} ? $params->{hal} : $params->{hal_from_item});
        $h //= (defined $params->{resource} ? $params->{resource} : $params->{resource_from_item});
        if (defined $h) {
            if (ref $h eq 'ARRAY') {
                @hal_from_item = @$h;
            } else { #if (not ref $h) {
                @hal_from_item = ( $h );
            }
        }
    } elsif (ref $arg eq 'ARRAY') {
        $params = {};
        @hal_from_item = @$arg;
    } else {
        $params = {};
        @hal_from_item = @args;
    }
    my $code = shift @hal_from_item;
    unshift(@hal_from_item,$c);
    unshift(@hal_from_item,$controller);
    unshift(@hal_from_item,$code);
    $params->{hal_from_item} = \@hal_from_item;
    $params->{operation} = $operation;
    $params->{resource_name} //= $controller->resource_name;
    
    my $resource = shift @hal_from_item;
    my $hal;
    if (ref $resource eq 'CODE') {
        $hal = $resource->(@hal_from_item);
    } else {
        $hal = $resource;
    }
    if (ref $hal eq Data::HAL::) {
        $resource = $hal->resource;
    }
    my $id;
    if (ref $resource eq 'HASH') {
        $id = $resource->{id};
    } elsif ((defined blessed($resource)) && $resource->can('id')) {
        $id = $resource->id;
    }
    return _create_journal($controller,$c,$id,$resource,$params);

}

sub get_api_journal_action_config {
    my ($path_part,$action_template,$journal_methods) = @_;
    my %journal_actions_found = map { $_ => 1 } @$journal_methods;
    if (exists $journal_actions_found{'item_base_journal'}) {
        my @result = ();
        if (exists $journal_actions_found{'journals_get'}) {
            my $action_config = Storable::dclone($action_template);
            $action_config->{Chained} = 'item_base_journal';
            $action_config->{PathPart} //= API_JOURNAL_RESOURCE_NAME;
            $action_config->{Args} = 0;
            $action_config->{Method} = 'GET';
            push(@result,$action_config,'journals_get');
        }
        if (exists $journal_actions_found{'journalsitem_get'}) {
            my $action_config = Storable::dclone($action_template);
            $action_config->{Chained} = 'item_base_journal';
            $action_config->{PathPart} //= API_JOURNAL_RESOURCE_NAME;
            $action_config->{Args} = 1;
            $action_config->{Method} = 'GET';
            push(@result,$action_config,'journalsitem_get');
        }
        if ((scalar @result) > 0) {
            push(@result,{
                Chained => '/',
                PathPart => $path_part,
                CaptureArgs => 1,
            },'item_base_journal');
            @result = reverse @result;
            return \@result;
        }
    }
    return [];
}

sub get_api_journal_query_params {
    my ($query_params) = @_;
    my @params = (defined $query_params ? @$query_params : ());
    push(@params,{
                param => 'operation',
                description => 'Filter for journal records by a specific CRUD operation ("create", "update" or "delete")',
                query => {
                    first => sub {
                        my $q = shift;
                        { 'operation' => $q };
                    },
                    second => sub { },
                },
            });
    return ['journal_query_params',
        is => 'ro',
        isa => 'ArrayRef',
        default => sub { #[ #sub {[
            \@params
        }, #], #]},
    ];
}

sub handle_api_item_base_journal {
    my ($controller,$c,$id) = @_;
    $c->stash->{item_id_journal} = $id;
    return undef;
}

sub handle_api_journals_get {
    my ($controller,$c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $item_id = $c->stash->{item_id_journal};
        last unless $controller->valid_id($c, $item_id);
        
        my $journals = get_journal_rs($controller,$c,$item_id);
        (my $total_count, $journals) = $controller->paginate_order_collection($c,$journals);

        my (@embedded, @links);
        for my $journal($journals->all) {
            push @embedded, hal_from_journal($controller,$c,$journal);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.API_JOURNAL_RESOURCE_NAME,
                href     => sprintf('/api/%s/%d/%s/%d', $journal->resource_name, $item_id,API_JOURNAL_RESOURCE_NAME,$journal->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/');

        push @links, $controller->collection_nav_links($page, $rows, $total_count, $c->request->path, $c->request->query_params);

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

sub handle_api_journalsitem_get {
    my ($controller,$c,$id) = @_;
    {
        my $item_id = $c->stash->{item_id_journal};
        last unless $controller->valid_id($c, $item_id);
        last unless $controller->valid_id($c, $id);

        my $journal = get_journalitem($c,$id);
        last unless $controller->resource_exists($c, journal => $journal);
        
        if ($journal->resource_id != $item_id) {
            $c->log->error("Journal record '" . $id . "' does not belong to '" . $controller->resource_name . '/' . $item_id . "'");
            $controller->error($c, HTTP_NOT_FOUND, "Entity 'journal' not found.");
            return;
        }

        my $hal = hal_from_journal($controller,$c,$journal);

        #my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
        #    (map { # XXX Data::HAL must be able to generate links with multiple relations
        #        s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
        #        s/rel=self/rel="item self"/;
        #        $_
        #    } $hal->http_headers),
        #), $hal->as_json);
        $c->response->headers($hal->http_headers);
        $c->response->body($hal->as_json);
        return;
    }
    return;
}

sub get_journal_rs {
    my ($controller,$c,$resource_id) = @_;
    my $rs = $c->model('DB')->resultset('journals')
        ->search({
            'resource_name' => $controller->resource_name,
            'resource_id' => $resource_id,
        },{
            columns => [qw(id operation resource_name resource_id timestamp username)],
            #alias => 'me',
        });
        
    if ($controller->can('journal_query_params')) {
        return $controller->apply_query_params($c,$controller->journal_query_params,$rs);
    }
    
    return $rs;
}

sub get_journalitem {
    my ($c,$id) = @_;
    my $journal_record = $c->model('DB')->resultset('journals')
        ->find({
            'id' => $id,
        });

    return $journal_record;
}


sub hal_from_journal {
    my ($controller,$c,$journal) = @_;

    my %resource = $journal->get_inflated_columns;
    {
        if (exists $resource{content}) {
            try {
                $resource{content} = _deserialize_content($journal->content_format,$journal->content);
            } catch($e) {
                $c->log->error("Failed to de-serialize journal content snapshot of journal record '" . $journal->id . "': $e");
                #$controller->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
                #return;
                last;
            };
            #delta stuff...
        }
    }
    
    my $resource_link = sprintf('/api/%s/%d', $journal->resource_name, $journal->resource_id);
    my $collection_link = sprintf('%s/%s/',$resource_link,API_JOURNAL_RESOURCE_NAME);
    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => $collection_link),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf('%s%d', $collection_link, $journal->id)),
            Data::HAL::Link->new(relation => sprintf('ngcp:%s',$journal->resource_name), href => $resource_link),
        ],
        relation => 'ngcp:'.API_JOURNAL_RESOURCE_NAME,
    );
    
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    );
    
    $resource{timestamp} = $datetime_fmt->format_datetime($resource{timestamp});
    delete $resource{resource_name};
    delete $resource{resource_id};
    delete $resource{content_format};
    $hal->resource({%resource});
    
    return $hal;
}

sub _serialize_content { #run this in eval only, deflate somehow inflicts a segfault in subsequent catalyst action when not consuming all args there.
    my ($format,$data) = @_;
    if (defined $format && defined $data) {
        if ($format eq CONTENT_JSON_FORMAT) {
            return JSON::to_json($data, { canonical => 1, pretty => 1, utf8 => 1 });
        } elsif ($format eq CONTENT_JSON_DEFLATE_FORMAT) {
            my $json = JSON::to_json($data, { canonical => 1, pretty => 1, utf8 => 1 });
            my $buf = '';
            IO::Compress::Deflate::deflate(\$json,\$buf) or die($DeflateError);
            return $buf;
        } elsif ($format eq CONTENT_STORABLE_FORMAT) {
            return Storable::nfreeze($data);
        }
    }
    return undef;
}

sub _deserialize_content {
    my ($format,$serialized) = @_;
    if (defined $format && defined $serialized) {
        if ($format eq CONTENT_JSON_FORMAT) {
            return JSON::from_json($serialized);
        } elsif ($format eq CONTENT_JSON_DEFLATE_FORMAT) {
            my $buf = '';
            IO::Uncompress::Inflate::inflate(\$serialized,\$buf) or die($DeflateError);
            return JSON::from_json($buf);
        } elsif ($format eq CONTENT_STORABLE_FORMAT) {
            return Storable::thaw($serialized);
        }
    }
    return undef;
}

sub _create_journal {
    my ($controller,$c,$id,$resource,$params) = @_;
    {
        my $content_format = (defined $params->{format} ? $params->{format} : CONTENT_DEFAULT_FORMAT);
        my %journal = (
                    operation => $params->{operation},
                    resource_name => $params->{resource_name},
                    #resource_id => $id,
                    timestamp => NGCP::Panel::Utils::DateTime::current_local->hires_epoch,
                    content_format => $content_format,
                );
        if (defined $id) {
            $journal{resource_id} = $id;
        }
        if (defined $params->{user}) {
            $journal{username} = $params->{user};
        } elsif (defined $c->user) {
            if($c->user->roles eq 'admin' || $c->user->roles eq 'reseller') {
                $journal{username} = $c->user->login;
            } elsif($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') {
                $journal{username} = $c->user->webusername . '@' . $c->user->domain->domain;
            } 
        }
        try {
            $journal{content} = _serialize_content($content_format,$resource);
            #my $test = 1 / 0;
        } catch($e) {
            $c->log->error("Failed to serialize journal content snapshot of '" . $params->{resource_name} . '/' . $id . "': $e");
            #$controller->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            #return;
            last;
        };
        try {
            return $c->model('DB')->resultset('journals')->create(\%journal);
        } catch($e) {
            $c->log->error("Failed to create journal record for '" . $params->{resource_name} . '/' . $id . "': $e");
            #$controller->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            #return;
            last;
        };
    }
    return undef;
}

1;