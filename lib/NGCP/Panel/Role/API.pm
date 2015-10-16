package NGCP::Panel::Role::API;
use Moose::Role;
use Sipwise::Base;

use Storable qw();
use JSON qw();
use JSON::Pointer;
use JSON::Pointer::Exception qw();
use HTTP::Status qw(:constants);
use Safe::Isa qw($_isa);
use Scalar::Util qw/blessed/;
use TryCatch;
use DateTime::Format::HTTP qw();
use DateTime::Format::RFC3339 qw();
use Types::Standard qw(InstanceOf);
use Regexp::Common qw(delimited); # $RE{delimited}
use HTTP::Headers::Util qw(split_header_words);
use NGCP::Panel::Utils::ValidateJSON qw();
#use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::Journal qw();
#use boolean qw(true);
#use Data::HAL qw();
#use Data::HAL::Link qw();

has('last_modified', is => 'rw', isa => InstanceOf['DateTime']);

sub get_valid_post_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};
    my $json =  $self->get_valid_raw_post_data(%params);
    return unless $self->require_wellformed_json($c, $media_type, $json);
    return JSON::from_json($json, { utf8 => 1 });
}

sub get_valid_raw_post_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};

    return unless $self->forbid_link_header($c);
    return unless $self->valid_media_type($c, $media_type);
    return unless $self->require_body($c);
    return $c->stash->{body};
}

sub get_valid_put_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};
    my $json =  $self->get_valid_raw_put_data(%params);
    return unless $json;
    return unless $self->require_wellformed_json($c, $media_type, $json);
    return JSON::from_json($json, { utf8 => 1 });
}

sub get_valid_raw_put_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};
    my $id = $params{id};

    return unless $self->valid_id($c, $id);
    return unless $self->forbid_link_header($c);
    return unless $self->valid_media_type($c, $media_type);
    return unless $self->require_body($c);
    return $c->stash->{body};
}

sub get_valid_patch_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};
    my $id = $params{id};
    my $ops = $params{ops} // [qw/replace copy/];

    return unless $self->valid_id($c, $id);
    return unless $self->forbid_link_header($c);
    return unless $self->valid_media_type($c, $media_type);
    return unless $self->require_body($c);
    my $json =  $c->stash->{body};
    return unless $self->require_wellformed_json($c, $media_type, $json);
    return unless $self->require_valid_patch($c, $json, $ops);

    return $json;
}

sub check_reload {
    my ($self, $c, $resource) = @_;
    my ($sip, $xmpp) = (1,1);

    if (delete $resource->{_skip_sip_reload} || $c->config->{features}->{debug}) {
        $sip = 0;
        $c->log->debug("skipping SIP reload");
    }
    if (delete $resource->{_skip_xmpp_reload} || $c->config->{features}->{debug}) {
        $xmpp = 0;
        $c->log->debug("skipping XMPP reload");
    }

    return ($sip, $xmpp);
}

sub validate_form {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $resource = $params{resource};
    my $form = $params{form};
    my $run = $params{run} // 1;
    my $exceptions = $params{exceptions} // [];
    my $form_params = $params{form_params} // {};
    push @{ $exceptions }, "external_id";

    my @normalized = ();

    # move {xxx_id} into {xxx}{id} for FormHandler
    foreach my $key(keys %{ $resource } ) {
        my $skip_normalize = grep {/^$key$/} @{ $exceptions };
        if($key =~ /^(.+)_id$/ && !$skip_normalize && !exists $resource->{$1}) {
            push @normalized, $1;
            $resource->{$1}{id} = delete $resource->{$key};
        }
    }

    # remove unknown keys
    my %fields = map { $_->name => $_ } $form->fields;
    $self->validate_fields($c, $resource, \%fields, $run);

    if($run) {
        # check keys/vals
        $form->process(params => $resource, posted => 1, %{$form_params} );
        unless($form->validated) {
            my $e = join '; ', map { 
                sprintf 'field=\'%s\', input=\'%s\', errors=\'%s\'', 
                    ($_->parent->$_isa('HTML::FormHandler::Field') ? $_->parent->name . '_' : '') . $_->name,
                    $_->input // '',
                    $_->errors->join(q())
            } $form->error_fields;
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Validation failed. $e");
            return;
        }
    }

    # move {xxx}{id} back into {xxx_id} for DB
    foreach my $key(@normalized) {
        next unless(exists $resource->{$key});
        $resource->{$key . '_id'} = defined($resource->{$key}{id}) ?
            int($resource->{$key}{id}) :
            $resource->{$key}{id};
        delete $resource->{$key};
    }

    return 1;
}

sub validate_fields {
    my ($self, $c, $resource, $fields, $run) = @_;
    
    for my $k (keys %{ $resource }) {
        #if($resource->{$k}->$_isa('JSON::XS::Boolean') || $resource->{$k}->$_isa('JSON::PP::Boolean')) {
        if($resource->{$k}->$_isa('JSON::PP::Boolean')) {
            $resource->{$k} = $resource->{$k} ? 1 : 0;
        }
        unless(exists $fields->{$k}) {
            delete $resource->{$k};
        }
        $resource->{$k} = DateTime::Format::RFC3339->format_datetime($resource->{$k})
            if $resource->{$k}->$_isa('DateTime');
        $resource->{$k} = $resource->{$k} + 0
            if(defined $resource->{$k} && (
               $fields->{$k}->$_isa('HTML::FormHandler::Field::Integer') ||
               $fields->{$k}->$_isa('HTML::FormHandler::Field::Money') ||
               $fields->{$k}->$_isa('HTML::FormHandler::Field::Float')) &&
               ($resource->{$k}->is_int || $resource->{$k}->is_decimal));

        if (defined $resource->{$k} &&
                $fields->{$k}->$_isa('HTML::FormHandler::Field::Repeatable') &&
                "ARRAY" eq ref $resource->{$k} ) {
            for my $elem (@{ $resource->{$k} }) {
                my ($subfield_instance) = $fields->{$k}->fields;
                my %subfields = map { $_->name => $_ } $subfield_instance->fields;
                $self->validate_fields($c, $elem, \%subfields, $run);
            }
        }

        # only do this for converting back from obj to hal
        # otherwise it breaks db fields with the \0 and \1 notation
        unless($run) {
            $resource->{$k} = $resource->{$k} ? JSON::true : JSON::false
                if(defined $resource->{$k} &&
                   $fields->{$k}->$_isa('HTML::FormHandler::Field::Boolean'));
        }
    }

    return 1;
}

sub error {
    my ($self, $c, $code, $message) = @_;

    $c->log->error("error $code - $message"); # TODO: user, trace etc
    
    $c->response->content_type('application/json');
    $c->response->status($code);
    $c->response->body(JSON::to_json({ code => $code, message => $message })."\n");
    $c->stash(api_error_message => $message);
    return;
}

sub forbid_link_header {
    my ($self, $c) = @_;
    return 1 unless $c->request->header('Link');
    $self->error($c, HTTP_BAD_REQUEST, "The request must not contain 'Link' headers. Instead assert relationships in the entity body.");
    return;
}

sub valid_media_type {
    my ($self, $c, $media_type) = @_;

    my $ctype = $c->request->header('Content-Type');
    $ctype =~ s/;\s+boundary.+$// if $ctype;
    my $type;
    if(ref $media_type eq "ARRAY") {
        $type = join ' or ', @{ $media_type };
        return 1 if $ctype && grep { $ctype eq $_ } @{$media_type};
    } else {
        $type = $media_type;
        return 1 if($ctype && index($ctype, $media_type) == 0);
    }
    $self->error($c, HTTP_UNSUPPORTED_MEDIA_TYPE, "Unsupported media type '" . ($ctype // 'undefined') . "', accepting $type only.");
    return;
}

sub require_body {
    my ($self, $c) = @_;
    return 1 if length $c->stash->{body};

    

    $self->error($c, HTTP_BAD_REQUEST, "This request is missing a message body.");
    return;
}

# returns Catalyst::Request::Upload
sub get_upload {
    my ($self, $c, $field) = @_;
    my $upload = $c->req->upload($field);
    return $upload if $upload;
    $self->error($c, HTTP_BAD_REQUEST, "This request is missing the upload part '$field' in body.");
    return;
}

sub require_preference {
    my ($self, $c) = @_;
    return 'minimal' unless $c->request->header('Prefer');
    my @preference = grep { 'return' eq $_->[0] } split_header_words($c->request->header('Prefer'));
    return $preference[0][1]
        if 1 == @preference && ('minimal' eq $preference[0][1] || 'representation' eq $preference[0][1]);
    $self->error($c, HTTP_BAD_REQUEST, "Header 'Prefer' must be either 'return=minimal' or 'return=representation'.");
}

sub require_wellformed_json {
    my ($self, $c, $media_type, $patch) = @_;
    my $ret;
    try {
        NGCP::Panel::Utils::ValidateJSON->new($patch);
        $ret = 1;
    } catch($e) {
        chomp $e;
        $self->error($c, HTTP_BAD_REQUEST, "The entity is not a well-formed '$media_type' document. $e");
    }
    return $ret;
}

sub allowed_methods_filtered {
    my ($self, $c) = @_;
    if($c->user->read_only) {
        my @methods = ();
        foreach my $m(@{ $self->allowed_methods }) {
            next unless $m =~ /^(GET|HEAD|OPTIONS)$/;
            push @methods, $m;
        }
        return \@methods;
    } else {
        return $self->allowed_methods; 
    }
}

sub allowed_methods {
    my ($self) = @_;
    #my $meta = $self->meta;
    #my @allow;
    #for my $method ($meta->get_method_list) {
    #    push @allow, $meta->get_method($method)->name
    #        if $meta->get_method($method)->can('attributes') &&
    #           grep { 'Allow' eq $_ } @{ $meta->get_method($method)->attributes };
    #}
    #return [sort @allow];
    return $self->attributed_methods('Allow');
}

sub attributed_methods {
    my ($self,$attribute) = @_;
    my $meta = $self->meta;
    my @attributed;
    for my $method ($meta->get_method_list) {
        push @attributed, $meta->get_method($method)->name
            if $meta->get_method($method)->can('attributes') &&
               grep { $attribute eq $_ } @{ $meta->get_method($method)->attributes };
    }
    return [sort @attributed];
}

sub valid_id {
    my ($self, $c, $id) = @_;
    return 1 if $id->is_integer;
    $self->error($c, HTTP_BAD_REQUEST, "Invalid id in request URI");
    return;
}

sub require_valid_patch {
    my ($self, $c, $json, $ops) = @_;

    my $valid_ops = { 
        'replace' => { 'path' => 1, 'value' => 1 },
        'copy' => { 'from' => 1, 'path' => 1 },
        'remove' => { 'path' => 1 },
        'add' => { 'path' => 1, 'value' => 1 },
        'test' => { 'path' => 1, 'value' => 1 },
        'move' => { 'from' => 1, 'path' => 1 },
    };
    for my $o(keys %{ $valid_ops }) {
        unless(grep { /^$o$/ } @{ $ops }) {
            delete $valid_ops->{$o};
        }
    }

    my $patch = JSON::from_json($json, { utf8 => 1 });
    unless(ref $patch eq "ARRAY") {
        $self->error($c, HTTP_BAD_REQUEST, "Body for PATCH must be an array.");
        return;
    }
    foreach my $elem(@{ $patch }) {
        unless(ref $elem eq "HASH") {
            $self->error($c, HTTP_BAD_REQUEST, "Array in body of PATCH must only contain hashes.");
            return;
        }
        unless(exists $elem->{op}) {
            $self->error($c, HTTP_BAD_REQUEST, "PATCH element must have an 'op' field.");
            return;
        }
        unless(exists $valid_ops->{$elem->{op}}) {
            $self->error($c, HTTP_BAD_REQUEST, "Invalid PATCH op '$elem->{op}', must be one of " . (join(', ', map { "'".$_."'" } keys %{ $valid_ops }) ));
            return;
        }
        my $tmpelem = Storable::dclone($elem);
        my $tmpops = Storable::dclone($valid_ops);
        my $op = delete $tmpelem->{op};
        foreach my $k(keys %{ $tmpelem }) {
            unless(exists $tmpops->{$op}->{$k}) {
                $self->error($c, HTTP_BAD_REQUEST, "Invalid PATCH key '$k' for op '$op', must be one of " . (join(', ', map { "'".$_."'" } keys %{ $valid_ops->{$op} }) ));
                return;
            }
            delete $tmpops->{$op}->{$k};
        }
        if(keys %{ $tmpops->{$op} }) {
            $self->error($c, HTTP_BAD_REQUEST, "Missing PATCH keys ". (join(', ', map { "'".$_."'" } keys %{ $tmpops->{$op} }) ) . " for op '$op'");
            return;
        }

    }

    return 1;
}

sub resource_exists {
    my ($self, $c, $entity_name, $resource) = @_;
    return 1 if $resource;
    $self->error($c, HTTP_NOT_FOUND, "Entity '$entity_name' not found.");
    return;
}

sub paginate_order_collection {
    my ($self, $c, $item_rs) = @_;

    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    my $order_by = $c->request->params->{order_by};
    my $direction = $c->request->params->{order_by_direction} // "asc";
    my $total_count = int($item_rs->count);
    $item_rs = $item_rs->search(undef, {
        page => $page,
        rows => $rows,
    });
    if ($order_by && $item_rs->result_source->has_column($order_by)) {
        my $me = $item_rs->current_source_alias;
        if (lc($direction) eq 'desc') {
            $item_rs = $item_rs->search(undef, {
                order_by => {-desc => "$me.$order_by"},
            });
            $c->log->debug("ordering by $me.$order_by DESC");
        } else {
            $item_rs = $item_rs->search(undef, {
                order_by => "$me.$order_by",
            });
            $c->log->debug("ordering by $me.$order_by");
        }
    }
    return ($total_count, $item_rs);
}

sub collection_nav_links {
    my ($self, $page, $rows, $total_count, $path, $params) = @_;

    $params = { %{ $params } }; #copy
    delete @{$params}{'page', 'rows'};
    my $rest_params = join( '&', map {"$_=".$params->{$_}} keys %{$params});
    $rest_params = $rest_params ? "&$rest_params" : "";

    my @links = (Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s%s', $path, $page, $rows, $rest_params)));

    if(($total_count / $rows) > $page ) {
        push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d%s', $path, $page + 1, $rows, $rest_params));
    }
    if($page > 1) {
        push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d%s', $path, $page - 1, $rows, $rest_params));
    }
    return @links;
}

sub apply_patch {
    my ($self, $c, $entity, $json, $optional_field_code_ref) = @_;
    my $patch = JSON::decode_json($json);
    try {
        for my $op (@{ $patch }) {
            my $coderef = JSON::Pointer->can($op->{op});
            die "invalid op '".$op->{op}."' despite schema validation" unless $coderef;
            for ($op->{op}) {
                if ('add' eq $_ or 'replace' eq $_) {
                    try {
                        $entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                    } catch($pe) {
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed $pe and $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity);
                                $entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    }
                } elsif ('remove' eq $_) {
                    try {
                        $entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                    } catch($pe) {
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed $pe and $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity);
                                $entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    }                    
                } elsif ('move' eq $_ or 'copy' eq $_) {
                    try {
                        $entity = $coderef->('JSON::Pointer', $entity, $op->{from}, $op->{path});
                    } catch($pe) {
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed $pe and $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity);
                                $entity = $coderef->('JSON::Pointer', $entity, $op->{from}, $op->{path});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    }                      
                } elsif ('test' eq $_) {
                    try {
                        die "test failed - path: $op->{path} value: $op->{value}\n"
                            unless $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                    } catch($pe) {
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed $pe and $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity);
                                die "test failed - path: $op->{path} value: $op->{value}\n"
                                    unless $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    }  
                }
            }
        }
    } catch($e) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "The entity could not be processed: $e");
        return;
    }
    return $entity;
}

#sub apply_fake_time {
#    my ($self, $c) = @_;
#    if (exists $ENV{API_FAKE_CLIENT_TIME} && $ENV{API_FAKE_CLIENT_TIME}) {
#        my $date = $c->request->header('Date');
#        if ($date) {
#            my $dt = NGCP::Panel::Utils::DateTime::from_rfc1123_string($date);
#            if ($dt) {
#                NGCP::Panel::Utils::DateTime::set_fake_time($dt->epoch);
#                $c->stash->{is_fake_time} = 1;
#                $c->log('using date header to fake system time: ' . NGCP::Panel::Utils::DateTime::to_string(NGCP::Panel::Utils::DateTime::current_local));
#                return;
#            }
#        }
#        NGCP::Panel::Utils::DateTime::set_fake_time();
#        $c->stash->{is_fake_time} = 0;
#        $c->log('resetting faked system time: ' . NGCP::Panel::Utils::DateTime::to_string(NGCP::Panel::Utils::DateTime::current_local));        
#    }
#}

#sub reset_fake_time {
#    my ($self, $c) = @_;
#    if (exists $ENV{API_FAKE_CLIENT_TIME} && $ENV{API_FAKE_CLIENT_TIME} && $c->stash->{fake_time}) {
#        NGCP::Panel::Utils::DateTime::set_fake_time();
#        $c->stash->{fake_time} = 0;
#        $c->log('resetting faked system time: ' . NGCP::Panel::Utils::DateTime::to_string(NGCP::Panel::Utils::DateTime::current_local));
#    }
#}
    
sub set_body {
    my ($self, $c) = @_;
    $c->stash->{body} = $c->request->body ? (do { local $/; $c->request->body->getline }) : '';
}

sub log_request {
    my ($self, $c) = @_;

    NGCP::Panel::Utils::Message->info(
        c    => $c,
        type => 'api_request',
        log  => $c->stash->{'body'},
    );
}

sub log_response {
    my ($self, $c) = @_;

    # TODO: should be put a UUID to stash in log_request and use it here to correlate
    # req/res lines?
    $c->forward(qw(Controller::Root render));
    $c->response->content_type('')
        if $c->response->content_type =~ qr'text/html'; # stupid RenderView getting in the way
    my $rc = '';
    if (@{ $c->error }) {
        my $msg = join ', ', @{ $c->error };
        $rc = NGCP::Panel::Utils::Message->error(
            c    => $c,
            type => 'api_response',
            log  => $msg,
        );
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
        $c->clear_errors;
    }
    NGCP::Panel::Utils::Message->info(
        c    => $c,
        type => 'api_response',
        log  => $c->response->body,
    );
}


sub item_rs {}
around 'item_rs' => sub {
    my ($orig, $self, @orig_params) = @_;
    my $item_rs = $self->$orig(@orig_params);
    return unless($item_rs);
    
    if ($self->can('query_params')) {
        return $self->apply_query_params($orig_params[0],$self->query_params,$item_rs);
    }
    
    return $item_rs;
};

sub apply_query_params {
    
    my ($self,$c,$query_params,$item_rs) = @_;
    # no query params defined in collection controller
    unless(@{ $query_params }) {
        return $item_rs;
    }

    foreach my $param(keys %{ $c->req->query_params }) {
        my @p = grep { $_->{param} eq $param } @{ $query_params };
        next unless($p[0]->{query}); # skip "dummy" query parameters
        my $q = $c->req->query_params->{$param}; # TODO: arrayref?
        $q =~ s/\*/\%/g;
        if(@p) {
            $item_rs = $item_rs->search($p[0]->{query}->{first}($q,$c), $p[0]->{query}->{second}($q,$c));
        }
    }
    return $item_rs;
    
}

sub is_true {
    my ($self, $v) = @_;
    my $val;
    if(ref $v eq "") {
        $val = $v;
    } else {
        $val = ${$v};
    }
    return 1 if(defined $val && $val == 1);
    return;
}

sub is_false {
    my ($self, $v) = @_;
    my $val;
    if(ref $v eq "") {
        $val = $v;
    } else {
        $val = ${$v};
    }
    return 1 unless(defined $val && $val == 1);
    return;
}

sub delay_commit {
    my ($self, $c, $guard) = @_;
    my $allow_delay_commit = 0;
    my $cfg = $c->config->{api_debug_opts};
    $allow_delay_commit = ((defined $cfg->{allow_delay_commit}) && $cfg->{allow_delay_commit} ? 1 : 0) if defined $cfg;    
    if ($allow_delay_commit) {
        my $delay = $c->request->header('X-Delay-Commit'); #('Expect');
        if ($delay && $delay =~ /\d+/ && $delay > 0 && $delay < 500) {
            $c->log->debug('using X-Delay-Commit header to delay db commit for ' . $delay . ' seconds');
            sleep($delay);
        }
    }
    $guard->commit();
}

sub add_create_journal_item_hal {
    my ($self,$c,@args) = @_;
    return NGCP::Panel::Utils::Journal::add_journal_item_hal($self,$c,NGCP::Panel::Utils::Journal::CREATE_JOURNAL_OP,@args);
}

sub add_update_journal_item_hal {
    my ($self,$c,@args) = @_;
    return NGCP::Panel::Utils::Journal::add_journal_item_hal($self,$c,NGCP::Panel::Utils::Journal::UPDATE_JOURNAL_OP,@args);
}

sub add_delete_journal_item_hal {
    my ($self,$c,@args) = @_;
    return NGCP::Panel::Utils::Journal::add_journal_item_hal($self,$c,NGCP::Panel::Utils::Journal::DELETE_JOURNAL_OP,@args);
}

sub get_journal_action_config {
    my ($class,$resource_name,$action_template) = @_;
    my $cfg = NGCP::Panel::Utils::Journal::get_journal_resource_config(NGCP::Panel->config,$resource_name);
    if ($cfg->{journal_resource_enabled}) {
        return NGCP::Panel::Utils::Journal::get_api_journal_action_config('api/' . $resource_name,$action_template,$class->attributed_methods('Journal'));
    }
    return [];
}

sub get_journal_query_params {
    my ($class,$query_params) = @_;
    return NGCP::Panel::Utils::Journal::get_api_journal_query_params($query_params);
}

sub handle_item_base_journal {
    return NGCP::Panel::Utils::Journal::handle_api_item_base_journal(@_);
}

sub handle_journals_get {
    return NGCP::Panel::Utils::Journal::handle_api_journals_get(@_);
}

sub handle_journalsitem_get {
    return NGCP::Panel::Utils::Journal::handle_api_journalsitem_get(@_);
}

sub handle_journals_options {
    return NGCP::Panel::Utils::Journal::handle_api_journals_options(@_);
}

sub handle_journalsitem_options {
    return NGCP::Panel::Utils::Journal::handle_api_journalsitem_options(@_);
}

sub handle_journals_head {
    return NGCP::Panel::Utils::Journal::handle_api_journals_head(@_);
}

sub handle_journalsitem_head {
    return NGCP::Panel::Utils::Journal::handle_api_journalsitem_head(@_);
}

sub get_journal_relation_link {
    my $cfg = NGCP::Panel::Utils::Journal::get_journal_resource_config(NGCP::Panel->config,$_[0]->resource_name);
    if ($cfg->{journal_resource_enabled}) {
        return NGCP::Panel::Utils::Journal::get_journal_relation_link(@_);
    }
    return ();
}

1;
# vim: set tabstop=4 expandtab:
