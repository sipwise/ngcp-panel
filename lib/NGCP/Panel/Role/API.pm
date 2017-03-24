package NGCP::Panel::Role::API;

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Journal/;

use NGCP::Panel::Utils::Generic qw(:all);
use boolean qw(true);
use Safe::Isa qw($_isa);
use Storable qw();
use JSON qw();
use JSON::Pointer;
use JSON::Pointer::Exception qw();
use HTTP::Status qw(:constants);
use Scalar::Util qw/blessed/;
use DateTime::Format::HTTP qw();
use DateTime::Format::RFC3339 qw();
use Types::Standard qw(InstanceOf);
use Regexp::Common qw(delimited); # $RE{delimited}
use HTTP::Headers::Util qw(split_header_words);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Journal qw();

#It is expected to work for all our 3 common cases:
#1. Body is the plain json data
#2. Multipart/form data with resource in "json" form field, and some uploads
#3. Some media data uploaded in request body, resource data passed as the query parameters
sub get_valid_data{
    my ($self, %params) = @_;

    my ($data,$resource);

    my $c = $params{c};
    my $method = $params{method};
    my $media_type = $params{media_type};
    my $json_media_type = $params{json_media_type};#for rare specific cases, like text/csv

    return unless $self->forbid_link_header($c);

    if(('POST' eq $method) || ('PUT' eq $method) ){
        $json_media_type //=  'application/json';
    }elsif('PATCH' eq $method){
        $json_media_type //= 'application/json-patch+json';
    }
    return unless $self->valid_media_type($c, $media_type);

    if(('PUT' eq $method) || ('PATCH' eq $method)){
        my $id = $params{id};
        return unless $self->valid_id($c, $id);
    }

    my ($json_raw,$json);
    if('multipart/form-data' eq $c->req->headers->content_type){
        return unless $self->require_uploads($c);
        $json_raw = $c->req->param('json');
    }else{
        return unless $self->require_body($c);
        $data = $c->stash->{body};
        $resource = $c->req->query_params;
    }

    #if($json_media_type =~/json/i){
    if($json_media_type eq 'application/json'
        || $json_media_type eq 'application/json-patch+json' ){

        $json_raw //= $data;

        return unless $self->require_wellformed_json($c, $json_media_type, $json_raw);
        $json = JSON::from_json($json_raw, { utf8 => 1 });
        if('PATCH' eq $method){
            my $ops = $params{ops} // [qw/replace copy/];
            return unless $self->require_valid_patch($c, $json, $ops);
        }
        return unless $self->get_uploads($c, $json, $params{uploads});
        $resource = $json;
    }

    return ($resource, $data);
}

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

    if(!@$exceptions && $form->can('validation_exceptions')){
        $exceptions = $form->validation_exceptions;
    }
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

    # remove unknown keys and prepare resource
    my %fields;
    foreach($form->fields){
        if($_->readonly){
            #Prepare resource for the PATCH considering readonly fields.
            #PATCH is supposed to take full item content and so will get readonly fields into resource too. And apply patch.
            #It leads to the situation when we may try to change some not existing fields in the DB
            #All readonly fields are considered as representation only and should never be applied.
            delete $resource->{$_->name};
            next;
        }
        $fields{$_->name} = $_;
    }
    $self->validate_fields($c, $resource, \%fields, $run);

    if($run) {
        # check keys/vals
        $form->process(params => $resource, posted => 1, %{$form_params} );
        unless($form->validated) {
            my $e = join '; ', map {
                my $in = (defined $_->input && ref $_->input eq 'HASH' && exists $_->input->{id}) ? $_->input->{id} : ($_->input // '');
                sprintf 'field=\'%s\', input=\'%s\', errors=\'%s\'',
                    ($_->parent->$_isa('HTML::FormHandler::Field') ? $_->parent->name . '_' : '') . $_->name,
                    $in,
                    join('', @{ $_->errors })
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
            next;
        }
        if($run){
            #Prepare resource for the PATCH considering readonly fields.
            #PATCH is supposed to take full item content and so will get readonly fields into resource too. And apply patch.
            #It leads to the situation when we may try to change some not existing fields in the DB
            #All readonly fields are considered as representation only and should never be applied.
            if($fields->{$k}->readonly) {
                delete $resource->{$k};
                next;
            }
        }
        $resource->{$k} = DateTime::Format::RFC3339->format_datetime($resource->{$k})
            if $resource->{$k}->$_isa('DateTime');
        $resource->{$k} = $resource->{$k} + 0
            if(defined $resource->{$k} && (
               $fields->{$k}->$_isa('HTML::FormHandler::Field::Integer') ||
               $fields->{$k}->$_isa('HTML::FormHandler::Field::Money') ||
               $fields->{$k}->$_isa('HTML::FormHandler::Field::Float')) &&
               (is_int($resource->{$k}) || is_decimal($resource->{$k})));

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
sub require_uploads {
    my ($self, $c) = @_;
    return 1 if $c->req->upload;
    $self->error($c, HTTP_BAD_REQUEST, "Thismultipart/form-data request is missing upload part.");
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

sub get_uploads {
    my ($self, $c, $json, $uploads) = @_;
    my (@upload_fields, %mime_types);
    if(!$uploads || ('ARRAY' ne ref $uploads && 'HASH' ne ref $uploads ) ){
        return;
    }elsif('ARRAY' eq ref $uploads){
        @upload_fields = @$uploads;
    }elsif('HASH' eq ref $uploads){
        @upload_fields = keys %$uploads;
        %mime_types = %$uploads;
    }
    my $ft;
    foreach my $field (@upload_fields){
        $json->{$field} = $self->get_upload($c, $field);
        if($mime_types{$field}){
            $ft //= File::Type->new();
            my $mime_type = $ft->mime_type($json->{$field}->slurp);
            if('ARRAY' ne ref $mime_types{$field}){
                $mime_types{$field} = [$mime_types{$field}];
            }
            if(!grep {$_ eq $mime_type} @{$mime_types{$field}}){
                $self->error($c, HTTP_UNSUPPORTED_MEDIA_TYPE, "Unsupported media type '" . ($mime_type // 'undefined') . "' for the $field, accepting ".join(" or ", @{$mime_types{$field}})." only.");
                return 0;
            }
        }
    }
    return 1;
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

# sub allowed_methods {
    # my ($self) = @_;
    # #my $meta = $self->meta;
    # #my @allow;
    # #for my $method ($meta->get_method_list) {
    # #    push @allow, $meta->get_method($method)->name
    # #        if $meta->get_method($method)->can('attributes') &&
    # #           grep { 'Allow' eq $_ } @{ $meta->get_method($method)->attributes };
    # #}
    # #return [sort @allow];
    # return $self->attributed_methods('Allow');
# }

# sub attributed_methods {
    # my ($self,$attribute) = @_;
    # my $meta = $self->meta;
    # my @attributed;
    # for my $method ($meta->get_method_list) {
        # push @attributed, $meta->get_method($method)->name
            # if $meta->get_method($method)->can('attributes') &&
               # grep { $attribute eq $_ } @{ $meta->get_method($method)->attributes };
    # }
    # return [sort @attributed];
# }

sub valid_id {
    my ($self, $c, $id) = @_;
    return 1 if is_int($id);
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
sub item_by_id_valid {
    my ($self, $c, $id) = @_;
    return unless $self->valid_id($c, $id);
    my $item = $self->item_by_id($c, $id);
    return unless $self->resource_exists($c, $self->item_name => $item);
    return $item;
}
sub resource_exists {
    my ($self, $c, $entity_name, $resource) = @_;
    return 1 if $resource;
    $self->error($c, HTTP_NOT_FOUND, "Entity '$entity_name' not found.");
    return;
}

sub paginate_order_collection {
    my ($self, $c, $items) = @_;
    my $params = {
        page => $c->request->params->{page} // 1,
        rows => $c->request->params->{rows} // 10,
        order_by => $c->request->params->{order_by},
        direction => $c->request->params->{order_by_direction} // "asc",
    };
    my($total_count, $item_rs);
    if('ARRAY' eq ref $items){
        ($total_count, $item_rs) = $self->paginate_order_collection_array($c, $items, $params);
    }else{
        ($total_count, $item_rs) = $self->paginate_order_collection_rs($c, $items, $params);
    }
    return ($total_count, $item_rs);
}

sub paginate_order_collection_array {
    my ($self, $c, $items, $params) = @_;
    my($page,$rows,$order_by,$direction) = @$params{qw/page rows order_by direction/};
    my $total_count = scalar @$items;
    if(defined $order_by ){
        if(defined $order_by && defined $direction && (lc($direction) eq 'desc') ){
            $items = [sort { $b->{$order_by} cmp  $a->{$order_by} } @$items];
        }else{
            $items = [sort { $a->{$order_by} cmp  $b->{$order_by} } @$items];
        }
    }
    $items = [splice(@$items, ( $page - 1 )*$rows, $rows) ];
    return ($total_count, $items);
}

sub paginate_order_collection_rs {
    my ($self, $c, $item_rs, $params) = @_;
    my($page,$rows,$order_by,$direction) = @$params{qw/page rows order_by direction/};

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

    my @links = (NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s%s', $path, $page, $rows, $rest_params)));

    if(($total_count / $rows) > $page ) {
        push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d%s', $path, $page + 1, $rows, $rest_params));
    }
    if($page > 1) {
        push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d%s', $path, $page - 1, $rows, $rest_params));
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
                                &$optional_field_code_ref(substr($op->{path},1),$entity,$op);
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

    NGCP::Panel::Utils::Message::info(
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
        $rc = NGCP::Panel::Utils::Message::error(
            c    => $c,
            type => 'api_response',
            log  => $msg,
        );
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
        $c->clear_errors;
    }
    NGCP::Panel::Utils::Message::info(
        c    => $c,
        type => 'api_response',
        log  => $c->response->body,
    );
}


#sub item_rs {}
sub item_rs {
    my ($self, @orig_params) = @_;
    my $item_rs = $self->_item_rs(@orig_params);
    return unless($item_rs);

    if ($self->can('query_params')) {
        return $self->apply_query_params($orig_params[0],$self->query_params,$item_rs);
    }

    return $item_rs;
}

sub apply_query_params {

    my ($self,$c,$query_params,$item_rs) = @_;
    # no query params defined in collection controller
    unless(@{ $query_params }) {
        return $item_rs;
    }

    foreach my $param(keys %{ $c->req->query_params }) {
        my @p = grep { $_->{param} eq $param } @{ $query_params };
        #todo: we can generate default filters for all item_rs fields here
        #the only reason not to do this is a security
        next unless($p[0]->{query} || $p[0]->{query_type} || $p[0]->{new_rs}); # skip "dummy" query parameters
        my $q = $c->req->query_params->{$param}; # TODO: arrayref?
        $q =~ s/\*/\%/g;
        $q = undef if $q eq "NULL"; # IS NULL translation
        if(@p) {
            if (defined $p[0]->{new_rs}) {
                #compose fresh rs based on current, to support set operations with filters:
                $item_rs = $p[0]->{new_rs}($c,$q,$item_rs);
            } elsif (defined $p[0]->{query} || defined $p[0]->{query_type}) {
                #regular chaining:
                my($sub_where,$sub_attributes) = $self->get_query_callbacks(\@p);
                $item_rs = $item_rs->search($sub_where->($q,$c), $sub_attributes->($q,$c));
            }
        }
    }
    return $item_rs;
}

sub get_query_callbacks{
    my ($self, $query_param_spec) = @_;
    #while believe that there is only one parameter
    my @p = @$query_param_spec;
    my($sub_where,$sub_attributes);
    if($p[0]->{query_type}){
        if('string_like' eq $p[0]->{query_type}){
            $sub_where = sub {my ($q, $c) = @_; { $p[0]->{param} => { like => $q } };};
        }elsif('string_eq' eq $p[0]->{query_type}){
            $sub_where = sub {my ($q, $c) = @_; { $p[0]->{param} => $q };};
        }
    }
    if($p[0]->{query}){
        $sub_where //= $p[0]->{query}->{first};
        $sub_attributes = $p[0]->{query}->{second};
    }
    $sub_attributes //= sub {};
    return ($sub_where,$sub_attributes);
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

#---------------- Entities staff
#---------------- default methods

sub hal_from_item {
    my ($self, $c, $item, $form, $params) = @_;
    my ($form_exceptions);
    if(!$form){
        ($form,$form_exceptions) = $self->get_form($c);
    }else{
        $form_exceptions = $params->{form_exceptions};
    }
    my $resource = $self->resource_from_item($c, $item, $form);

    $resource = $self->process_hal_resource($c, $item, $resource, $form);
    my $links = $self->hal_links($c, $item, $resource, $form) // [];
    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $self->get_item_id($c, $item))),
            NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:".$self->resource_name, href => sprintf("/api/%s/%s", $self->resource_name, $self->get_item_id($c, $item))),
            @$links
        ],
        relation => 'ngcp:'.$self->resource_name,
    );
    if($form){
        $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            $form_exceptions ? (exceptions => $form_exceptions) : (),
            run => 0,
        );
    }
    $resource->{id} = $self->get_item_id($c, $item);
    $hal->resource({%$resource});
    return $hal;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form, $params) = @_;
    my ($form_exceptions, $process_extras);
    ($form, $form_exceptions, $process_extras) = @{$params}{qw/form form_exceptions process_extras/};

    if(!$form){
        ($form, $form_exceptions) = $self->get_form($c);
    }

    if($form){
        return unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            $form_exceptions ? (exceptions => $form_exceptions) : (),
        );
        return unless $resource;
    }

    $old_resource //= $self->resource_from_item($c, $item, $form);

    $process_extras //= {};

    return unless $self->process_form_resource($c, $item, $old_resource, $resource, $form, $process_extras);
    return unless $resource;
    return unless $self->check_duplicate($c, $item, $old_resource, $resource, $form, $process_extras);
    return unless $self->check_resource($c, $item, $old_resource, $resource, $form, $process_extras);

    $item = $self->update_item_model($c, $item, $old_resource, $resource, $form, $process_extras);

    return $item, $form, $form_exceptions;
}

#------ dummy & default methods

sub query_params {
    return [
    ];
}

sub _set_config{
    return {};
}

sub check_duplicate{
    my($self, $c, $item, $old_resource, $resource, $form) = @_;
    return 1;
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form) = @_;
    return 1;
}

#process_form_resource - added as method for custom preparation form data,like:
#   my $ft = File::Type->new();
#   my $content_type = $ft->mime_type(${$process_extras->{binary_ref}});
#   if($type eq 'mac') {
#       $resource->{mac_image} = ${$process_extras->{binary_ref}};
#       $resource->{mac_image_type} = $content_type;
#   } else {
#       $resource->{front_image} = ${$process_extras->{binary_ref}};
#       $resource->{front_image_type} = $content_type;
#   }
#
#etc. Method still can be used as exit point, if form data processing can be performed due to incorrect input data
#used in update_item
sub process_form_resource {
    my($self, $c, $item, $old_resource, $resource, $form) = @_;
    return $resource;
}


#process_hal_resource is rarely used method, which intnded to transform somehow db resource data to the hal we want
#something like:
#$resource{contract_id} = delete $resource{peering_contract_id};
#used at least in hal_from_item
sub process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    return $resource;
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    return [];
}

sub get_form {
    my($self, $c) = @_;
    return ;
}

sub get_item_id{
    my($self, $c, $item, $resource, $form) = @_;
    return int($item->id);
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub resource_from_item{
    my($self, $c, $item) = @_;
    my $res;
    if('HASH' eq ref $item){
        $res = $item;
    }else{
        $res = { $item->get_inflated_columns };
    }
    return $res;
}

sub update_item_model{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    $item->update($resource);
    return $item;
}


#------ accessors ---

sub dispatch_path {
    my $self = shift;
    return '/api/'.$self->resource_name.'/';
}

sub relation {
    my $self = shift;
    return 'http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name;
}

#------ /accessors ---
sub return_representation{
    my($self, $c, %params) = @_;
    my($hal, $response, $item, $form, $preference, $form_exceptions) = @params{qw/hal response item form preference form_exceptions/};

    $preference //= $self->require_preference($c);
    return unless $preference;
    $hal //= $self->hal_from_item($c, $item, $form, \%params );
    $response //= HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
        $hal->http_headers,
    ), $hal->as_json);

    if ('minimal' eq $preference) {
        $c->response->status(HTTP_NO_CONTENT);
        $c->response->header(Preference_Applied => 'return=minimal');
        $c->response->body(q());
    } else {
        $c->response->headers($response->headers);
        $c->response->header(Preference_Applied => 'return=representation');
        $c->response->body($response->content);
    }
}

sub return_representation_post{
    my($self, $c, %params) = @_;
    my($hal, $response, $item, $form, $preference, $form_exceptions) = @params{qw/hal response item form preference form_exceptions/};

    $preference //= $self->require_preference($c);
    return unless $preference;
    $hal //= $self->hal_from_item($c, $item, $form, \%params );
    $response //= HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
        $hal->http_headers,
    ), $hal->as_json);

    $c->response->status(HTTP_CREATED);
    $c->response->header(Location => sprintf('/%s%d', $c->request->path, $self->get_item_id($c, $item)));
    if ('minimal' eq $preference) {
        $c->response->body(q());
    }else{
        $c->response->body($response->content);
    }
}


sub return_csv(){
    my($self,$c) = @_;
    try{
        my $filename = $self->check_create_csv($c);
        return unless $filename;
        $c->response->header ('Content-Disposition' => "attachment; filename=\"$filename\"");
        $c->response->content_type('text/csv');
        $c->response->status(200);
        $self->create_csv($c);
        $c->response->body(q());
    }catch($e){
        $self->error($c, HTTP_BAD_REQUEST, $e);
    }
}

sub return_requested_type {
    my ($self, $c, $id, $item) = @_;
    try{
        my($data_ref,$mime_type,$filename) = $self->get_item_binary_data($c, $id, $item);
        $filename  //= $self->item_name.''.$self->get_item_id($c, $item);
        $mime_type //= 'application/octet-stream' ;

        $c->response->header ('Content-Disposition' => 'attachment; filename="' . $filename  . '"');
        $c->response->content_type( $mime_type );
        $c->response->body($$data_ref);
    }catch($e){
        $self->error($c, HTTP_BAD_REQUEST, $e);
    }
}
1;
# vim: set tabstop=4 expandtab:
