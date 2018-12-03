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
use Encode qw( encode_utf8 );

use HTTP::Headers::Util qw(split_header_words);
use Data::Compare;
use Data::HAL qw();
use Data::HAL::Link qw();
use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Journal qw();

#It is expected to work for all our 3 common cases:
#1. Body is the plain json data
#2. Multipart/form data with resource in "json" form field, and some uploads
#3. Some media data uploaded in request body, resource data passed as the query parameters
sub get_valid_data{
    my ($self, %params) = @_;

    my ($data,$resource,$non_json_data);

    my $c = $params{c};
    my $method = $params{method} // uc($c->request->method);
    my $media_type = $params{media_type};
    my $resource_media_type = $params{resource_media_type};#for rare specific cases, like text/csv

    return unless $self->forbid_link_header($c);

    if ($method =~ /^(GET|PUT|POST)$/) {
        $resource_media_type //=  'application/json';
    } elsif ($method eq 'PATCH') {
        $resource_media_type //= 'application/json-patch+json';
    }
    return unless $self->valid_media_type($c, $media_type);

    if ($method =~ /^(PUT|PATCH)$/) {
        my $id = $params{id};
        return unless $self->valid_id($c, $id);
    }

    my ($json_raw,$json_decoded);
    if ($c->req->headers->content_type eq 'multipart/form-data') {
        return unless $self->require_uploads($c);
        $json_raw = encode_utf8($c->req->param('json'));
    } elsif ($c->req->headers->content_type eq 'application/json'
        && 'GET' ne $method) {
        return unless $self->require_body($c);
        #overwrite for the first variant of the dual upload
        $resource_media_type = 'application/json';
        $json_raw = $c->stash->{body};
    } else {
        if ('GET' ne $method) {
            return unless $self->require_body($c);
            $data = $c->stash->{body};
        }
        $resource = $c->req->query_params;
        $non_json_data = 1;
    }

    if ($resource_media_type eq 'application/json' ||
        $resource_media_type eq 'application/json-patch+json' ) {

        $json_raw //= $data;

        return unless $self->require_wellformed_json($c, $resource_media_type, $json_raw);
        if ($c->req->headers->content_type eq 'multipart/form-data') {
            $json_decoded = JSON::from_json($json_raw, { utf8 => 0 });
        } else {
            $json_decoded = JSON::from_json($json_raw, { utf8 => 1 });
        }
        if ($method eq 'PATCH') {
            my $ops = $params{ops} // [qw/replace copy/];
            return unless $self->require_valid_patch($c, $json_decoded, $ops);
        }
        return unless $self->get_uploads($c, $json_decoded, $params{uploads}, $params{form});
        $resource = $json_decoded;
        $non_json_data = 0;
    }

    return ($resource, $data, $non_json_data);
}

#method to take any informative input, i.e.
#   - json body,
#   - json part of multiform
#   - request_params
sub get_info_data {
    my ($self, $c) = @_;
    my $ctype = $self->get_content_type($c) // '';
    my $resource = $c->request->params;
    my ($resource_json,$resource_json_raw) = (undef,'');
    if ('multipart/form-data' eq $ctype) {
        $resource_json = $c->req->param('json');
        delete $resource->{json};
    } elsif ('application/json' eq $ctype) {
        $resource_json_raw = $c->stash->{body};
    }
    if($resource_json_raw){
        $resource_json = JSON::from_json($resource_json_raw, { utf8 => 1 });
    }
    {
        #check that we don't provide different data via different request type
        my @common_keys = map { exists $resource->{$_} ? $_ : () }keys %$resource_json;
        my (%resource_sub,%resource_json_sub);
        @resource_sub{@common_keys} = @{$resource}{@common_keys};
        @resource_json_sub{@common_keys} = @{$resource_json}{@common_keys};
        if(!Compare(\%resource_sub,\%resource_json_sub)){
            return;
        }
    }
    return {%$resource,%$resource_json};
}

sub get_valid_post_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};
    my $json =  $self->get_valid_raw_post_data(%params);
    return unless $self->valid_media_type($c, $media_type);
    return unless $self->require_preference($c);
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
    my $item = $params{item};
    my $run = $params{run} // 1;
    my $form_params = $params{form_params} // {};

    my $exceptions = [
        grep {m/_id$/} map {"".$_->name} $form->fields
    ];


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
        $fields{$_->name} = $_;
    }
    $self->validate_fields($c, $resource, \%fields, $run);

    if($run) {
        # check keys/vals
        $form->process(
            params => $resource, 
            posted => 1, 
            %{$form_params}, 
            item => $item, 
            no_update => 1
        );
        unless($form->validated) {
            my $e = join '; ', map {
                my $in = (defined $_->input && ref $_->input eq 'HASH' && exists $_->input->{id}) ? $_->input->{id} : ($_->input // '');
                $in //= '';
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
                "ARRAY" eq ref $resource->{$k}) {
            my ($subfield_instance) = $fields->{$k}->fields;
            if ($subfield_instance) {
                my %subfields = map { $_->name => $_ } $subfield_instance->fields;
                for my $elem (@{ $resource->{$k} }) {
                    $self->validate_fields($c, $elem, \%subfields, $run);
                }
            }
        }
        if (defined $resource->{$k} &&
                $fields->{$k}->$_isa('HTML::FormHandler::Field::Compound') &&
                "HASH" eq ref $resource->{$k}) {
            my @compound_subfields = $fields->{$k}->fields;
            if (@compound_subfields) {
                my %subfields = map { $_->name => $_ } @compound_subfields;
                $self->validate_fields($c, $resource->{$k}, \%subfields, $run);
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
use Carp qw/longmess/;
use Data::Dumper;
print longmess(Dumper([$code, $message]));
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

sub get_content_type {
    my ($self, $c, $media_type) = @_;
    my $ctype = $c->request->header('Content-Type');
    $ctype =~ s/;\s+boundary.+$// if $ctype;
    return $ctype;
}

sub valid_media_type {
    my ($self, $c, $media_type) = @_;

    my $ctype = $self->get_content_type($c);
    my $type;
    if(ref $media_type eq "ARRAY") {
        $type = join ' or ', @{ $media_type };
        return 1 if $ctype && grep { index($ctype, $_) == 0 } @{$media_type};
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
    return 1 if $c->req->upload || $self->get_config('backward_allow_empty_upload');
    $self->error($c, HTTP_BAD_REQUEST, "This multipart/form-data request is missing upload part.");
    return;
}

# returns Catalyst::Request::Upload
sub get_upload {
    my ($self, $c, $field, $required) = @_;
    my $upload = $c->req->upload($field);
    return $upload if $upload;
    if($required){
        $self->error($c, HTTP_BAD_REQUEST, "This request is missing the upload part '$field' in body.");
    }
    return;
}

sub get_uploads {
    my ($self, $c, $json, $uploads, $form) = @_;
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
        my $required = $form ? $form->field($field)->required : 1;
        my $upload = $self->get_upload($c, $field, $required);
        if(!$upload && !$required){
            next;
        }
        $json->{$field} = $upload;
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
    my $prefer_default = 'minimal';
    return $prefer_default unless $c->request->header('Prefer');
    my $ngcp_ua_header = $c->request->header("NGCP-UserAgent") // '';
    my @preference = grep { 'return' eq $_->[0] } split_header_words($c->request->header('Prefer'));
    return $preference[0][1]
        if 1 == @preference && $preference[0][1] =~ /^(minimal|representation)$/;
    return $preference[0][1]
        if 1 == @preference && $preference[0][1] eq 'internal' &&
                $ngcp_ua_header eq "NGCP::API::Client";
    return $prefer_default;
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
#
#old:
#sub config_allowed_roles {
#    return [qw/admin subscriber /];
#}
#
#also possible:
#sub config_allowed_roles {
#    return {
#        'Default' => [qw/admin reseller subscriberadmin/],
#        #GET will use default
#        'POST'    => [qw/admin reseller/],
#        'PUT'     => [qw/admin reseller/],
#        'PATCH'   => [qw/admin reseller/],
#        'Journal' => [qw/admin/],
#    };
#}
#
#sub config_allowed_roles {
#    return [ [qw/admin subscriber/], [qw/admin/] ];
#   #where [qw/admin/] - is Journal roles spec
#}
#

sub config_allowed_roles {
    return [qw/admin reseller/];
}

sub get_allowed_roles {
    my($self, $roles_config_in, $method) = @_;

    my $roles_config = $roles_config_in // $self->config_allowed_roles;
    my ($allowed_roles_default, $allowed_roles_journal, $allowed_roles_per_methods);

    if('HASH' eq ref $roles_config){
        $allowed_roles_default = delete $roles_config->{Default};
        $allowed_roles_per_methods = {map {
            $_ => $roles_config->{$_} // $allowed_roles_default;
        } @{ $self->allowed_methods }, 'Journal' };
    }else{
        $allowed_roles_default = 'ARRAY' eq ref $roles_config ? $roles_config : [$self->config_allowed_roles];
        if ('ARRAY' eq ref $roles_config->[0]) {
            $allowed_roles_default = $roles_config->[0];
            $allowed_roles_journal = $roles_config->[1] // $allowed_roles_default;
        }
        $allowed_roles_per_methods = {map {
            $_ => $allowed_roles_default;
        } @{ $self->allowed_methods }};
        $allowed_roles_per_methods->{Journal} = $allowed_roles_journal;
    }
    return $method ? $allowed_roles_per_methods->{$method} : $allowed_roles_per_methods;
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

sub valid_uuid {
    my ($self, $c, $uuid) = @_;
    return 1 if $uuid =~ /^[a-f0-9\-]+$/;
    $self->error($c, HTTP_BAD_REQUEST, "Invalid uuid in request URI");
    return;
}

sub require_valid_patch {
    my ($self, $c, $json, $ops) = @_;

    my $valid_ops = {
        'replace' => { 'path' => 1, 'value' => 1 },
        'copy' => { 'from' => 1, 'path' => 1 },
        'remove' => { 'path' => 1, 'value' => 0, 'index' => 0 },# 0 means optional
        'add' => { 'path' => 1, 'value' => 1, mode => {
                required => 0,
                allowed_values => [qw/append/],
            },
        },
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
        #remove optional op parameters, so only mandatory will stay
        foreach my $k(keys %{ $tmpops->{$op} }) {
            if (!ref $tmpops->{$op}->{$k} && !$tmpops->{$op}->{$k}) {
                delete $tmpops->{$op}->{$k};
            } elsif (ref $tmpops->{$op}->{$k} eq 'HASH') {
                if (defined $tmpops->{$op}->{$k}->{allowed_values} && $elem->{$k}) {
                    if (!grep {$elem->{$k} eq $_} @{$tmpops->{$op}->{$k}->{allowed_values}}) {
                        $self->error($c, HTTP_BAD_REQUEST, "Invalid PATCH op '".$tmpops->{$op}."' modifier '$k' value '".$elem->{$k}."'. Allowed values are '". (join("', '", @{$tmpops->{$op}->{$k}->{allowed_values}}) ) . "'");
                    }
                }
                if (exists $tmpops->{$op}->{$k}->{required} && ! $tmpops->{$op}->{$k}->{required}) {
                    #by default all op spec keys are required, so only those with required = 0 shouldn't be cjecked in $elem
                    delete $tmpops->{$op}->{$k};
                }
            }
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

sub dont_count_collection_total {
    my ($self, $c) = @_;
    my $no_count = defined $c->req->query_params->{no_count} ? $c->req->query_params->{no_count} : 0;
    if ( !$no_count || ($no_count ne 'true' && $no_count ne '1' ) ) {
        $no_count = 0;
    } else {
        $no_count = 1;
    }
    return $no_count;
}

sub define_collection_infinite_pager {
    my ($self, $c, $items_count, $item_rs, $rows_on_page, $no_count) = @_;
    $no_count //= $self->dont_count_collection_total($c);
    if (! defined $c->stash->{collection_infinite_pager_stop}) {
        #$item_rs->pager->entries_on_this_page leads to the count query
        my $entries_on_this_page = $items_count // $item_rs->count;
        $c->stash->{collection_infinite_pager_stop} = (( $entries_on_this_page < $rows_on_page ) and $no_count );
    }
}

sub paginate_order_collection_rs {
    my ($self, $c, $item_rs, $params) = @_;
    my($page,$rows,$order_by,$direction) = @$params{qw/page rows order_by direction/};

    my $result_class = $item_rs->result_class();

    my $total_count;
    my $no_count = $self->dont_count_collection_total($c);
    if ( !$no_count ) {
        $total_count = int($item_rs->count);
    }

    $item_rs = $item_rs->search(undef, {
        page => $page,
        rows => $rows,
    });
    $self->define_collection_infinite_pager($c, undef, $item_rs, $rows, $no_count);
    if ($order_by) {
        my $explicit_order_col_spec;
        if ($self->can('order_by_cols')) {
            my($explicit_order_cols,$explicit_order_cols_params) = $self->order_by_cols($c);
            $explicit_order_col_spec = $explicit_order_cols->{$order_by};
            $explicit_order_cols_params //= {};
            if ( exists $explicit_order_cols_params->{$order_by}->{join} ) {
                $item_rs = $item_rs->search(undef, {
                    join => $explicit_order_cols_params->{$order_by}->{join},
                });
            }
        }
        if ($explicit_order_col_spec || $item_rs->result_source->has_column($order_by)) {
            my $col = $explicit_order_col_spec || $item_rs->current_source_alias . '.' . $order_by;
            if (lc($direction) eq 'desc') {
                $item_rs = $item_rs->search(undef, {
                    order_by => {-desc => $col},
                });
                $c->log->debug("ordering by $col DESC");
            } else {
                $item_rs = $item_rs->search(undef, {
                    order_by => "$col",
                });
                $c->log->debug("ordering by $col");
            }
        }
    }
    my $result_class_after = $item_rs->result_class();
    if($result_class ne $result_class_after){
        $item_rs->result_class($result_class);
    }

    return ($total_count, $item_rs);
}

sub collection_nav_links {
    my ($self, $c, $page, $rows, $total_count, $path, $params) = @_;

    $path   //= $c->request->path;
    $params //= $c->request->params;

    my $params_default = $self->get_mandatory_params($c, 'collection');
    $params = {
        'HASH' eq ref $params_default ? %$params_default : (),
    #$params has priority
        'HASH' eq ref $params ? %{ $params } : ()
    }; #copy
    delete @{$params}{'page', 'rows'};
    my $rest_params = join( '&', map {"$_=".(defined $params->{$_} ? $params->{$_} : '');} keys %{$params});
    $rest_params = $rest_params ? "&$rest_params" : "";

    my @links = (Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s%s', $path, $page, $rows, $rest_params)));

    if ( (! defined $total_count
            && ! $c->stash->{collection_infinite_pager_stop} )
        || ( defined $total_count && ($total_count / $rows) > $page ) ) {

        push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d%s', $path, $page + 1, $rows, $rest_params));
    }
    if ($page > 1) {
        push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d%s', $path, $page - 1, $rows, $rest_params));
    }
    return @links;
}

sub get_patch_append_point {
    my ($self, $c, $entity_root, $path, $value) = @_;
    $entity_root //= {};
    my $entity_sub = $entity_root;
    my $entity_sub_ref;
    $path =~s/^\///;
    my @keys = split /\//, $path;
    print Dumper \@keys;
    my $key_next;
    for (my $i = 0; $i < @keys; $i++) {
        my $key = $keys[$i];
        $key_next = $i < $#keys ? $keys[$i+1] : undef;
        print Dumper [$i,$key, $key_next,$entity_sub,$entity_root];
        if ($key =~/^-?\d+$/) {
            if ($key_next) {
                $entity_sub->[$key] = $key_next =~/^\d+$/ ? [] : {};
            } else {
                #$entity_sub->[$key] = undef;
                $entity_sub->[$key] = ref $value eq 'ARRAY' ? [] :  ref $value eq 'HASH' ? {} : undef;#$value;
            }
            $entity_sub_ref = \$entity_sub->[$key];
            $entity_sub = $entity_sub->[$key];
        } else {
            if ($key_next) {
                $entity_sub->{$key} = $key_next =~/^\d+$/ ? [] : {};
             } else {
                #$entity_sub->[$key] = undef;
                $entity_sub->{$key} = ref $value eq 'ARRAY' ? [] :  ref $value eq 'HASH' ? {} : undef;
            }
            $entity_sub_ref = \$entity_sub->{$key};
            $entity_sub = $entity_sub->{$key};
        } 
    }
    use Data::Dumper;
    print Dumper ["entity_root",$entity_root,"entity_sub_ref",$entity_sub_ref];
    return $entity_root, $entity_sub_ref;
}

#this method expands the newly added ops/modes to the know patch ops.
sub process_patch_description {
    my ($self, $c, $entity, $patch) = @_;
    my $patch_diff = [];
    my $op_iterator = -1;
    my $entity_diff = {add => [], remove => []};
    my $entity_root = {};
    for my $op (@{ $patch }) {
        $op_iterator++;
        if ($op->{op} eq 'add' && $op->{mode} && $op->{mode} eq 'append') {
            splice @$patch, $op_iterator, 1;
            $op->{path} =~s/\/\-$//;#we will add it if element exists
            #we force value to array as append means that we will add values to some (existing or newly created) array.
            #So we will not add create /path as a plain string value, but only as array
            my $value_new = ref $op->{value} eq 'ARRAY' ? $op->{value} : [$op->{value}];
            my $value_current = JSON::Pointer->get($entity, $op->{path});
            my ($entity_diff_sub,$entity_append_point) = $self->get_patch_append_point($c,  $entity_root, $op->{path}, $value_new);
            push @{$entity_diff->{add}}, [$entity_diff_sub,$entity_append_point];
            if (!$value_current) {
                push @$patch_diff, {"op" => "add", "path" => $op->{path}, "value" => $value_new};
            } elsif (ref $value_current eq 'ARRAY') {
                push @$patch_diff, map {{"op" => "add", "path" => $op->{path}.'/-', "value" => $_}} @{$op->{value}};
            } else {
                die("invalid attempt to append in not-array path '".$op->{path}."'");
            }
        } elsif ($op->{op} eq 'remove' && $op->{value}) {
            splice @$patch, $op_iterator, 1;
            my $remove_index = $op->{index};#no default value, undefined means "remove all"
            my $found_count = 0;
            my $removal_done = 0;
            my $values_to_remove;
            if (ref $op->{value} eq 'ARRAY') {
                undef $remove_index;#??? - this is according to AC, but during meeting it sounded different
                $values_to_remove = $op->{value};
            } else {
                $values_to_remove = [$op->{value}];
            }
            my $value_current = JSON::Pointer->get($entity, $op->{path});
            foreach my $value_to_remove (@$values_to_remove) {
                #we are not able to request full array removal with exact value
                if (ref $value_current eq 'ARRAY') {
                    for (my $i=0; $i < @$value_current; $i++) {
                        # 0 if different, 1 if equal
                        if (compare($value_current->[$i], $value_to_remove)) {
                            if ( defined $remove_index ) {
                                if ($found_count == $remove_index) {
                                #if we want to use patch info to try to make clear changes, we shouldn't use replace
                                #from the other pov, if we requested 10000 removals, we will have 10000 new op entries
                                    push @$patch_diff, {"op" => "remove", "path" => $op->{path}.'/'.$i };
                                    $removal_done = 1;
                                    last;
                                } else {
                                    $found_count++;
                                }
                            } else {
                                push @$patch_diff, {"op" => "remove", "path" => $op->{path}.'/'.$i };
                            }
                        }
                    }
                    if ($removal_done) {
                        last;
                    }
                } else { #current value is not an array
                    if (compare($value_current, $value_to_remove)) {
                        push @$patch_diff, {"op" => "remove", "path" => $op->{path} };
                    }
                }
            }
            #we went through all the filter values and still didn't find enough elements to satisfy requested index
            if ($remove_index && $found_count < $remove_index ) {
                die("delete index $remove_index out of bounds");
            }
        } elsif ($op->{op} eq 'add') {
            my $path = $op->{path};
            my ($entity_diff_sub,$entity_append_point) = $self->get_patch_append_point($c,  $entity_root, $op->{path}, $op->{value});
        }
    }
    push @$patch, @$patch_diff;
    use Data::Dumper;
    print Dumper [$entity_diff, $entity_root];
    return $entity_diff, $entity_root;
}

sub apply_patch {
    my ($self, $c, $entity, $json, $optional_field_code_ref) = @_;
    my $patch = JSON::decode_json($json);
    my ($entity_diff, $entity_root);
    try {
        (undef, $entity_root) = $self->process_patch_description($c, Storable::dclone($entity), $patch);
        for my $op (@{ $patch }) {
            my $coderef = JSON::Pointer->can($op->{op});
            die "invalid op '".$op->{op}."' despite schema validation" unless $coderef;
            for ($op->{op}) {
                if ('add' eq $_ or 'replace' eq $_) {
                    try {
                        #$entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                        $entity_diff = $coderef->('JSON::Pointer', $entity_root, $op->{path}, $op->{value});
                    } catch($pe) {
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed($pe) && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity,$op);
                                $entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    }
                } elsif ('remove' eq $_) {
                    try {
                        #$entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                        $entity_diff = $coderef->('JSON::Pointer', $entity_root, $op->{path});
                    } catch($pe) {
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed $pe && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
                                &$optional_field_code_ref(substr($op->{path},1),$entity);
                                $entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                            }
                        } else {
                            die($pe); #->rethrow;
                        }
                    }
                } elsif ('move' eq $_ or 'copy' eq $_) {
                    try {
                        #$entity = $coderef->('JSON::Pointer', $entity, $op->{from}, $op->{path});
                        $entity_diff = $coderef->('JSON::Pointer', $entity_root, $op->{path});
                    } catch($pe) {
                        if (defined $optional_field_code_ref && ref $optional_field_code_ref eq 'CODE') {
                            if (blessed $pe && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
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
                            if (blessed $pe && $pe->isa('JSON::Pointer::Exception') && $pe->code == JSON::Pointer::Exception->ERROR_POINTER_REFERENCES_NON_EXISTENT_VALUE) {
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
    print Dumper [$patch,$entity_diff];
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
    $c->stash->{body} = $c->request->body ? (do { local $/ = undef; $c->request->body->getline }) : '';
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
    my ($response_body, $params_data) = $self->filter_log_response(
            $c,
            $c->response->body,
            $c->request->parameters,
        );
    NGCP::Panel::Utils::Message::info(
        c    => $c,
        type => 'api_response',
        log  => $response_body,
        data => $params_data,
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

    foreach my $param(_get_sorted_query_params($c,$query_params)) {
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
    #use DBIx::Class::Helper::ResultSet::Explain qw();
    #use Data::Dumper;
    #$c->log->debug(Dumper(DBIx::Class::Helper::ResultSet::Explain::explain($item_rs)));
    return $item_rs;
}

sub _get_sorted_query_params {

    my ($c,$query_params) = @_;
    #use Data::Dumper;
    #$c->log->debug('request params: ' . Dumper($c->req->query_params));
    #$c->log->debug('request param keys: ' . Dumper(keys %{$c->req->query_params}));
    #$c->log->debug('supported filters: ' . Dumper($query_params));
    my %query_params_map = ();
    if (defined $query_params) {
        foreach my $param (@$query_params) {
            if (exists $param->{param} and defined $param->{param}) {
                $query_params_map{$param->{param}} = $param;
            }
        }
    }
    #$c->log->debug('supported filter map: ' . Dumper(\%query_params_map));
    my @sorted = sort {
        (exists $query_params_map{$a} and exists $query_params_map{$a}->{new_rs}) <=> (exists $query_params_map{$b} and exists $query_params_map{$b}->{new_rs});
    } keys %{$c->req->query_params};
    #$c->log->debug('request params: ' . Dumper($c->req->query_params));
    #$c->log->debug('request params sorted: ' . Dumper(\@sorted));
    return @sorted;

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
sub get_config {
    my ($self, $key) = @_;
    if ($key) {
        return $self->config->{$key};
    }
    return $self->config;
}

sub get_item_config {
    my ($self) = shift;
    if ('collection' eq $self->get_config('interface_type')) {
        my $item_obj_name = $self;
        $item_obj_name =~s/=HASH.*$//;
        $item_obj_name .= 'Item';
        if ($item_obj_name->can('get_config')) {
            return $item_obj_name->get_config(@_);
        }
    }
}

sub get_collection_config {
    my ($self) = shift;
    if ('item' eq $self->get_config('interface_type')) {
        my $collection_obj_name = $self;
        $collection_obj_name =~s/=HASH.*$//;
        $collection_obj_name =~ s/Item$//;
        if ($collection_obj_name->can('get_config')) {
            return $collection_obj_name->get_config(@_);
        }
    }
}

sub get_collection_obj {
    my ($self) = shift;
    my $collection_obj_name = $self;
    $collection_obj_name =~s/=HASH.*$//;
    if ('item' eq $self->get_config('interface_type')) {
         $collection_obj_name =~ s/Item$//;
    }
    return $collection_obj_name;
}

#---------------- default methods

sub hal_from_item {
    my ($self, $c, $item, $form, $params) = @_;
    if(!$form){
        ($form) = $self->get_form($c);
    }
    my $resource = $params->{resource};
    $resource //= $self->resource_from_item($c, $item, $form, $params);
    $resource = $self->process_hal_resource($c, $item, $resource, $form, $params);
    return unless $resource;
    my $links = $self->hal_links($c, $item, $resource, $form, $params) // [];
    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(
                relation => 'collection',
                href => $self->apply_mandatory_parameters($c, 'collection', sprintf(
                    "/api/%s/",
                    $self->resource_name
                ), $item, $resource, $params)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(
                relation => 'self',
                href => $self->apply_mandatory_parameters($c, 'item', sprintf(
                    "%s%s",
                    $self->dispatch_path,
                    $self->get_item_id($c, $item)
                ), $item, $resource, $params),
            ),
            Data::HAL::Link->new(
                relation => "ngcp:".$self->resource_name,
                href => $self->apply_mandatory_parameters($c, 'item', sprintf(
                    "/api/%s/%s",
                    $self->resource_name,
                    $self->get_item_id($c, $item)
                ), $item, $resource, $params)
            ),
            @$links,
            $self->get_journal_relation_link($c, $self->get_item_id($c, $item)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );
    if (!$self->get_config('dont_validate_hal')) {
        if($form){
            $self->validate_form(
                c => $c,
                resource => $resource,
                form => $form,
                run => 0,
            );
        }
    }
    $resource->{id} = $self->get_item_id($c, $item);
    $resource = $self->post_process_hal_resource($c, $item, $resource, $form);
    $hal->resource({%$resource});
    return $hal;
}

sub get_mandatory_params {
    my ($self, $c, $href_type, $item, $resource, $params) = @_;
    #href type - item or collection

    my $mandatory_parameters = $c->stash->{mandatory_parameters};
    if ($mandatory_parameters) {
        #we will not set stash->{mandatory_parameters} here, this is reserved for well validated parameters
        return $mandatory_parameters;
    }
    my $mandatory_params_config;
    if ($self->get_config('interface_type') eq $href_type) {
        $mandatory_params_config = $self->get_config('mandatory_parameters');
    } elsif ($href_type eq 'collection') {
        $mandatory_params_config = $self->get_collection_config('mandatory_parameters');
    } elsif ($href_type eq 'item') {
        $mandatory_params_config = $self->get_item_config('mandatory_parameters');
    }
    if ($mandatory_params_config) {
        #mandatory params config will always look as:
        #HashRef {
        # policy (e.g. - all, any, single) => { parameter_name => {type info,validator and other}}
        # OR policy (e.g. - all, any, single) => [/mandatory params/]
        #}
        my $request_data = $self->get_info_data($c);
        my $resource = {
            'HASH' eq ref $resource ? %$resource : (),
            #overwrite from specially created source
            'HASH' eq ref $params ? %$params : (),
        };
        $mandatory_parameters = {
            map { $resource->{$_}
                ? ( $_ => $resource->{$_} )
                : ( $request_data->{$_}
                    ? ( $_ => $request_data->{$_} )
                    : () ) }
            map { 'ARRAY' eq ref $_ ? ( @$_ ) : ( keys %$_ ) }
                values %$mandatory_params_config
        };
    }
    return $mandatory_parameters;
}

sub apply_mandatory_parameters {
    my ($self, $c, $href_type, $href, $item, $resource, $params) = @_;
    #href type - item or collection
    my $mandatory_parameters = $self->get_mandatory_params($c, $href_type, $item, $resource, $params);
    if ($mandatory_parameters) {
        my $mandatory_params_str = join('&', map {
               $_.'='.$mandatory_parameters->{$_}
            } keys %$mandatory_parameters );
        return $href.( $mandatory_params_str ? (($href !~ /\?/) ? '?' : '&').$mandatory_params_str : '' );
    }
    return $href;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form, $params) = @_;
    my $process_extras;
    ($form, $process_extras) = @{$params}{qw/form process_extras/};  # TODO: form can be passed twice?

    $old_resource //= $self->resource_from_item($c, $item, $form);
    $process_extras //= {};
    if(!$form){
        ($form) = $self->get_form($c, 'edit');
    }

    if($form){
        last unless $self->pre_process_form_resource($c, $item, $old_resource, $resource, $form, $process_extras);
        return unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            item => $item,
        );
        return unless $resource;
    }

    return unless $self->process_form_resource($c, $item, $old_resource, $resource, $form, $process_extras);
    return unless $resource;
    return unless $self->check_duplicate($c, $item, $old_resource, $resource, $form, $process_extras);
    return unless $self->check_resource($c, $item, $old_resource, $resource, $form, $process_extras);

    $item = $self->update_item_model($c, $item, $old_resource, $resource, $form, $process_extras);

    return $item, $form, $process_extras;
}

sub update_item_model{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    $item->update($resource);
    return $item;
}
#---------------- /default methods

#------ dummy & default accessors methods

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

#pre_process_form_resource, process_form_resource - added as method for custom preparation form data,like:
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
sub pre_process_form_resource {
    my($self, $c, $item, $old_resource, $resource, $form) = @_;
    return $resource;
}

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

sub post_process_hal_resource {
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

sub get_list{
    my ($self) = shift;
    return $self->item_rs(@_);
}

sub get_item_id{
    my($self, $c, $item, $resource, $form, $params) = @_;
    return int(blessed $item ? $item->id : $item->{id});
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


sub post_process_commit{
    my($self, $c, $action, $item, $old_resource, $resource, $form, $process_extras) = @_;
    return;
}

sub validate_request {
    my ($self, $c) = @_;
    return 1;
}

#------ /dummy & default accessors methods

sub check_transaction_control{
    my ($self, $c, $action, $step, %params) = @_;
    my $res = 1;#means that transaction control is on framework side, 0 - on controller side
    my $transaction_config = $self->get_config('own_transaction_control');
    if (!$transaction_config) {
        $res = 1;
    } else {
        if ($transaction_config->{ALL}) {
            $res = 0;
        } elsif ( ('HASH' eq ref $transaction_config->{$action} && $transaction_config->{$action}->{$step} )
            || ( $transaction_config->{$action} && !ref $transaction_config->{$action}) ) {
            $res = 0;
        }
    }
    return $res;
}

sub get_transaction_control{
    my $self = shift;
    my($c, $action, $step, %params) = @_;
    my $schema = $params{schema} // $c->model('DB');
    $action //= uc $c->request->method;
    $step //= 'init';
    if($self->check_transaction_control($c, $action, $step, %params)){
        #todo: put it into class variables?
        my $til_config = $self->get_config('set_transaction_isolation');
        if ($til_config) {
            my $transaction_isolation_level =
                ( (length $til_config > 1 )
                    && lc $til_config ne 'default' )
                ? $til_config
                : 'READ COMMITTED';
            $c->model('DB')->set_transaction_isolation($transaction_isolation_level);
        }
        $c->stash->{transaction_quard} = $schema->txn_scope_guard;
        return $c->stash->{transaction_quard};
    }
    return;
}

sub complete_transaction{
    my $self = shift;
    my($c, $action, $step, %params) = @_;
    my $schema = $params{schema} // $c->model('DB');
    my $guard = $params{guard} // $c->stash->{transaction_quard};
    $action //= uc $c->request->method;
    $step //= 'commit';
    if($self->check_transaction_control($c, $action, $step, %params)){
        $guard->commit;
        $c->stash->{transaction_quard} = undef;
    }
    return;
}

# $response_body can only be modified as a string due to its nature of being the raw response body
sub filter_log_response {
    my ($self, $c, $response_body, $params_data) = @_;

    return ($response_body, $params_data);
}
#------ accessors ---

sub resource_name{
    return $_[0]->config->{resource_name};
}

#need it for sub config, when config is not defined yet, so we just format known resource_name properly
sub dispatch_path{
    return '/api/'.($_[0]->resource_name // $_[1]).'/';
}

sub relation {
    my $self = shift;
    return 'http://purl.org/sipwise/ngcp-api/#rel-'.$_[0]->resource_name;
}

sub item_name{
    return $_[0]->config->{item_name};
}

sub allowed_methods{
    return $_[0]->config->{allowed_methods};
}

#------ /accessors ---
sub return_representation{
    my($self, $c, %params) = @_;
    my($hal, $response, $item, $preference, $form) = @params{qw/hal response item preference form/};

    $preference //= $self->require_preference($c);
    return unless $preference;
    $hal //= $self->hal_from_item($c, $item, $form, \%params);
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
    my($hal, $response, $item, $preference, $form) = @params{qw/hal response item preference form/};

    $preference //= $self->require_preference($c);
    return unless $preference;

    $c->response->status(HTTP_CREATED);

    if ($item) {
        $hal //= $self->hal_from_item($c, $item, $form, \%params);
        $response //= HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            $hal->http_headers,
        ), $hal->as_json);
        my ($self_hal_link) = grep { $_->relation->as_string eq 'self' } @{$hal->links};
        $c->response->header( Location => $self_hal_link->href->as_string );
    }

    if ('minimal' eq $preference || !$response) {
        $c->response->body(q());
    }else{
        $c->response->body($response->content);
    }
}

sub return_csv{
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

sub check_return_type {
    my ($self, $c, $requested_type, $allowed_types) = @_;
    if (!$allowed_types) {
        my $action_config = $self->get_config('action');
        $allowed_types = $action_config->{GET}->{ReturnContentType};
    }
    #while not strict requirement to the config
    my $result = 1;
    if ($allowed_types) {
        if ( (!ref $allowed_types && $requested_type ne 'binary' && index($requested_type, $allowed_types) < 0)
            ||
            ( ref $allowed_types eq 'ARRAY'
                && !grep {index($requested_type, $_) > -1} @$allowed_types
            )
        ) {
            $result = 0;
        }
    }
    if (!$result) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Requested unknown type '$requested_type', supported types: ".((ref $allowed_types eq 'ARRAY')? join (',', @$allowed_types) :  $allowed_types )."." );
    }
    return $result;
}

sub mime_type_from_query_params {
    my ($self, $c) = @_;
    my @mime_type_parameter = grep {defined $_->{type} && $_->{type} eq 'mime_type'} @{$self->get_collection_obj->query_params};
    if (scalar @mime_type_parameter) {
        my $query_params = $c->req->query_params;
        my $query_mime_type_param = $mime_type_parameter[0]->{param};
        my $mime_type_extension = $query_params->{$query_mime_type_param};
        if ($mime_type_extension) {
            my $mime_type = extension_to_mime_type($mime_type_extension);
            $c->log->debug("mime_type_from_query_params: requested parameter '$query_mime_type_param' with value '".($mime_type_extension ? $mime_type_extension : "undefined")."' and recognized as '".($mime_type ? $mime_type : "undefined")."'");
            return $mime_type;
        }
    }
    return;
}

sub supported_mime_types_extensions {
    my ($self) = @_;
    my $action_config = $self->get_item_config('action');
    my $allowed_types = $action_config->{GET}->{ReturnContentType};
    if ($allowed_types && ref $allowed_types eq 'ARRAY') {
        return [map {mime_type_to_extension($_)} grep {$_ ne 'application/json'} @$allowed_types];
    }
    return [];
}


sub return_requested_type {
    my ($self, $c, $id, $item, $return_type) = @_;
    try{
        if($return_type eq 'text/csv') {
            $self->return_csv($c);
            return;
        }
        if (!$self->can('get_item_binary_data')) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Method not implemented.");
        }
        my($data_ref,$mime_type,$filename) = $self->get_item_binary_data($c, $id, $item, $return_type);
        $filename  //= $self->item_name.''.$self->get_item_id($c, $item);
        $mime_type //= 'application/octet-stream' ;

        #here we rely on the get_item_binary_data return. If data is empty, it means that get_item_binary_data cared about proper error already
        if(!$data_ref){
            return;
        }
        $c->response->header ('Content-Disposition' => 'attachment; filename="' . $filename  . '"');
        $c->response->content_type( $mime_type );
        $c->response->body($$data_ref);
    }catch($e){
        $self->error($c, HTTP_BAD_REQUEST, $e);
    }
}

1;
# vim: set tabstop=4 expandtab:
