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
use Sereal::Decoder qw();
use Sereal::Encoder qw();

use constant CREATE_JOURNAL_OP => 'create';
use constant UPDATE_JOURNAL_OP => 'update';
use constant DELETE_JOURNAL_OP => 'delete';
use constant _JOURNAL_OPS => { CREATE_JOURNAL_OP.'' => 1, UPDATE_JOURNAL_OP.'' => 1, DELETE_JOURNAL_OP.'' => 1 };

use constant OPERATION_DEFAULT_ENABLED => 0;

use constant API_JOURNAL_RESOURCE_NAME => 'journal';
use constant API_JOURNALITEMTOP_RESOURCE_NAME => 'recent'; #empty to disable
use constant JOURNAL_RESOURCE_DEFAULT_ENABLED => 0;

use constant CONTENT_JSON_FORMAT => 'json';
use constant CONTENT_STORABLE_FORMAT => 'storable';
use constant CONTENT_JSON_DEFLATE_FORMAT => 'json_deflate';
use constant CONTENT_SEREAL_FORMAT => 'sereal';
use constant _CONTENT_FORMATS => { CONTENT_JSON_FORMAT.'' => 1, CONTENT_STORABLE_FORMAT.'' => 1, CONTENT_JSON_DEFLATE_FORMAT.'' => 1, CONTENT_SEREAL_FORMAT.'' => 1 };

use constant CONTENT_DEFAULT_FORMAT => CONTENT_JSON_FORMAT;

use constant API_JOURNAL_RELATION => 'ngcp:'.API_JOURNAL_RESOURCE_NAME;
#use constant API_JOURNALITEM_RELATION => 'ngcp:journalitem';

use constant JOURNAL_FIELDS => ['id', 'operation', 'resource_name', 'resource_id', 'timestamp', 'username'];

sub add_journal_item_hal {
    my ($controller,$c,$operation,@args) = @_;
    my $cfg = _get_api_journal_op_config($c,$controller->resource_name,$operation);
    if ($cfg->{operation_enabled}) {
        my $arg = $args[0];
        my @hal_from_item = ();
        my $params;
        my $id;
        my $id_name = 'id';
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
            $id_name = $params->{id_name} if defined $params->{id_name}; 
            $id = $params->{id} if defined $params->{id};             
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
        $params->{format} //= $cfg->{format};
        
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
        if (!defined $id) {
            if (ref $resource eq 'HASH') {
                $id = $resource->{$id_name};
            } elsif ((defined blessed($resource)) && $resource->can($id_name)) {
                $id = $resource->$id_name;
            }
        }
        return _create_journal($controller,$c,$id,$resource,$params);
    }
    return 1;
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
        if (exists $journal_actions_found{'journals_options'}) {
            my $action_config = Storable::dclone($action_template);
            $action_config->{Chained} = 'item_base_journal';
            $action_config->{PathPart} //= API_JOURNAL_RESOURCE_NAME;
            $action_config->{Args} = 0;
            $action_config->{Method} = 'OPTIONS';
            push(@result,$action_config,'journals_options');
        }
        if (exists $journal_actions_found{'journals_head'}) {
            my $action_config = Storable::dclone($action_template);
            $action_config->{Chained} = 'item_base_journal';
            $action_config->{PathPart} //= API_JOURNAL_RESOURCE_NAME;
            $action_config->{Args} = 0;
            $action_config->{Method} = 'HEAD';
            push(@result,$action_config,'journals_head');
        }        
        if (exists $journal_actions_found{'journalsitem_get'}) {
            my $action_config = Storable::dclone($action_template);
            $action_config->{Chained} = 'item_base_journal';
            $action_config->{PathPart} //= API_JOURNAL_RESOURCE_NAME;
            $action_config->{Args} = 1;
            $action_config->{Method} = 'GET';
            push(@result,$action_config,'journalsitem_get');
        }
        if (exists $journal_actions_found{'journalsitem_options'}) {
            my $action_config = Storable::dclone($action_template);
            $action_config->{Chained} = 'item_base_journal';
            $action_config->{PathPart} //= API_JOURNAL_RESOURCE_NAME;
            $action_config->{Args} = 1;
            $action_config->{Method} = 'OPTIONS';
            push(@result,$action_config,'journalsitem_options');
        }
        if (exists $journal_actions_found{'journalsitem_head'}) {
            my $action_config = Storable::dclone($action_template);
            $action_config->{Chained} = 'item_base_journal';
            $action_config->{PathPart} //= API_JOURNAL_RESOURCE_NAME;
            $action_config->{Args} = 1;
            $action_config->{Method} = 'HEAD';
            push(@result,$action_config,'journalsitem_head');
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
                description => 'Filter for journal items by a specific CRUD operation ("create", "update" or "delete")',
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
            my $hal = hal_from_journal($controller,$c,$journal);
            $hal->_forcearray(1);
            push @embedded,$hal;
            my $link = get_journal_relation_link($journal,$item_id,$journal->id);
            $link->_forcearray(1);
            push @links,$link;
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
        my $journal = undef;
        if (API_JOURNALITEMTOP_RESOURCE_NAME and $id eq API_JOURNALITEMTOP_RESOURCE_NAME) {
            $journal = get_top_journalitem($controller,$c,$item_id);
        } elsif ($controller->valid_id($c, $id)) {
            $journal = get_journalitem($c,$id);
        } else {
            last;
        }
        
        last unless $controller->resource_exists($c, journal => $journal);
        
        if ($journal->resource_id != $item_id) {
            $c->log->error("Journal item '" . $id . "' does not belong to '" . $controller->resource_name . '/' . $item_id . "'");
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
        $c->response->headers(HTTP::Headers->new($hal->http_headers));
        $c->response->body($hal->as_json);
        return;
    }
    return;
}

sub handle_api_journals_options {
    my ($controller, $c, $id) = @_;
    my @allowed_methods = ('OPTIONS');
    my %journal_actions_found = map { $_ => 1 } @{ $controller->attributed_methods('Journal') };
    if (exists $journal_actions_found{'journals_get'}) {
        push(@allowed_methods,'GET');
        if (exists $journal_actions_found{'journals_head'}) {
            push(@allowed_methods,'HEAD');
        }    
    }
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ',@allowed_methods),
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => \@allowed_methods })."\n");
    return;
}

sub handle_api_journalsitem_options {
    my ($controller, $c, $id) = @_;
    my @allowed_methods = ('OPTIONS');
    my %journal_actions_found = map { $_ => 1 } @{ $controller->attributed_methods('Journal') };
    if (exists $journal_actions_found{'journalsitem_get'}) {
        push(@allowed_methods,'GET');
        if (exists $journal_actions_found{'journalsitem_head'}) {
            push(@allowed_methods,'HEAD');
        }    
    }
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ',@allowed_methods),
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => \@allowed_methods })."\n");
    return;
}

sub _has_journal_method {

    my ($controller, $action) = @_;
    my %journal_actions_found = map { $_ => 1 } @{ $controller->attributed_methods('Journal') };
    return exists $journal_actions_found{$action};
    
}

sub handle_api_journals_head {
    my ($controller, $c) = @_;
    if (_has_journal_method($controller,'journals_get')) {
        $c->forward('journals_get');
        $c->response->body(q());
        return;
    } else {
        $c->log->error("journals_get action not implemented: " . ref $controller);
        $c->response->status(HTTP_METHOD_NOT_ALLOWED);
        $c->response->body(q());
        return;
    }
}

sub handle_api_journalsitem_head {
    my ($controller, $c) = @_;
    if (_has_journal_method($controller,'journalsitem_get')) {
        $c->forward('journalsitem_get');
        $c->response->body(q());
        return;
    } else {
        $c->log->error("journalsitem_get not implemented: " . ref $controller);
        $c->response->status(HTTP_METHOD_NOT_ALLOWED);
        $c->response->body(q());
        return;
    }
}

sub get_journal_rs {
    my ($controller,$c,$resource_id,$all_columns) = @_;
    my $rs = $c->model('DB')->resultset('journals')
        ->search({
            'resource_name' => $controller->resource_name,
            'resource_id' => $resource_id,
        },($all_columns ? undef : {
            columns => JOURNAL_FIELDS,
            #alias => 'me',
        }));
        
    if ($controller->can('journal_query_params')) {
        return $controller->apply_query_params($c,$controller->journal_query_params,$rs);
    }
    
    return $rs;
}

sub get_journalitem {
    my ($c,$id) = @_;
    my $journal = $c->model('DB')->resultset('journals')
        ->find({
            'id' => $id,
        });

    return $journal;
}

sub get_top_journalitem {
    my ($controller,$c,$resource_id) = @_;
    return get_top_n_journalitems($controller,$c,$resource_id,1,1)->[0];
}

sub get_top_n_journalitems {
    my ($controller,$c,$resource_id,$n,$all_columns) = @_;
    my @journals = get_journal_rs($controller,$c,$resource_id,$all_columns)->search(undef,{
        page => 1,
        rows => $n,
        order_by => {-desc => "id"},
    })->all;
    return \@journals;
}
            
sub hal_from_journal {
    my ($controller,$c,$journal) = @_;

    my %resource = $journal->get_inflated_columns;
    {
        if (exists $resource{content}) {
            try {
                $resource{content} = _deserialize_content($journal->content_format,$journal->content);
            } catch($e) {
                $resource{content} = undef;
                $c->log->error("Failed to de-serialize content snapshot of journal item '" . $journal->id . "': $e");
                #$controller->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
                #return;
                last;
            };
            #delta stuff...
        }
    }
    
    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            get_journal_relation_link($journal,$journal->resource_id,undef,'collection'),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            get_journal_relation_link($journal,$journal->resource_id,$journal->id,'self'),
            Data::HAL::Link->new(relation => sprintf('ngcp:%s',$journal->resource_name),
                href => sprintf('/api/%s/%d', $journal->resource_name, $journal->resource_id)),
        ],
        relation => API_JOURNAL_RELATION, #API_JOURNALITEM_RELATION,
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

sub get_journal_relation_link {
    
    my ($resource,$item_id,$id,$relation) = @_;
    my $resource_name = undef;
    if (ref $resource eq 'HASH') {
        $resource_name = $resource->{resource_name};
    } elsif ((defined blessed($resource)) && $resource->can('resource_name')) { #both controllers and journal rows
        $resource_name = $resource->resource_name;
    } elsif (!ref $resource) {
        $resource_name = $resource;
    }
    if (defined $resource_name) {
        if (defined $id) {
            return Data::HAL::Link->new(
                    relation => ($relation // API_JOURNAL_RELATION), #API_JOURNALITEM_RELATION),
                    href     => sprintf('/api/%s/%d/%s/%d', $resource_name, $item_id,API_JOURNAL_RESOURCE_NAME,$id),
                );
        } else {
            return Data::HAL::Link->new(
                    relation => ($relation // API_JOURNAL_RELATION),
                    href     => sprintf('/api/%s/%d/%s/', $resource_name, $item_id,API_JOURNAL_RESOURCE_NAME),
                )
        }
    }
    return undef;

}

sub get_api_journal_op_config {
    my ($config,$resource_name,$operation) = @_;
    return _get_journal_op_config($config->{api_journal},undef,$resource_name,$operation);
}

sub _get_api_journal_op_config {
    return _get_journal_op_config($_[0]->config->{api_journal},@_);
}

sub _get_journal_op_config {
    my ($cfg,$c,$resource_name,$operation) = @_;
    #my $cfg = $c->config->{$section};
    my $format = CONTENT_DEFAULT_FORMAT;
    my $operation_enabled = OPERATION_DEFAULT_ENABLED;
    if (defined $cfg && exists $cfg->{$resource_name}) {
        $cfg = $cfg->{$resource_name};
        if (ref $cfg eq 'HASH') {
            if (ref $cfg->{operations} eq 'ARRAY') {
                foreach my $op (@{ $cfg->{operations} }) {
                    if (exists _JOURNAL_OPS->{$op}) {
                        if ($operation eq $op) {
                            $operation_enabled = 1;
                            last;
                        }
                    } else {
                        $c->log->error("Invalid '$resource_name' operation to log in journals: $op") if defined $c;
                    }
                }
            }
            if (defined $cfg->{format}) {
                if (exists _CONTENT_FORMATS->{$cfg->{format}}) {
                    $format = $cfg->{format};
                } else {
                    $c->log->error("Invalid journal content format for resource '$resource_name': $cfg->{format}") if defined $c;
                }
            }
        }
    }
    return { format => $format, operation_enabled => $operation_enabled};
    
}

sub get_journal_resource_config {
    my ($config,$resource_name) = @_;
    my $cfg = $config->{api_journal};
    my $journal_resource_enabled = JOURNAL_RESOURCE_DEFAULT_ENABLED;
    if (defined $cfg && exists $cfg->{$resource_name}) {
        $cfg = $cfg->{$resource_name};
        if (ref $cfg eq 'HASH') {
            if (defined $cfg->{enabled}) {
                if ($cfg->{enabled}) {
                    $journal_resource_enabled = 1;
                } else {
                    $journal_resource_enabled = 0;
                }
            }
        }
    }
    return { journal_resource_enabled => $journal_resource_enabled };
    
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
        } elsif ($format eq CONTENT_SEREAL_FORMAT) {
            return Sereal::Encoder::encode_sereal($data);
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
        } elsif ($format eq CONTENT_SEREAL_FORMAT) {
            return Sereal::Decoder::decode_sereal($serialized);
        }
    }
    return undef;
}

sub _create_journal {
    my ($controller,$c,$id,$resource,$params) = @_;
    {
        my $content_format = ((defined $params->{format} and exists _CONTENT_FORMATS->{$params->{format}}) ? $params->{format} : CONTENT_DEFAULT_FORMAT);
        my $operation = ((defined $params->{operation} and exists _JOURNAL_OPS->{$params->{operation}}) ? $params->{operation} : undef);
        if (!defined $operation) {
            $c->log->error("Invalid '$params->{resource_name}' operation to log in journals: $operation");
            last;
        }
        my %journal = (
                    operation => $operation,
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
            $c->log->error("Failed to create journal item for '" . $params->{resource_name} . '/' . $id . "': $e");
            #$controller->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            #return;
            last;
        };
    }
    return undef;
}

1;