package NGCP::Panel::Role::API;
use Moose::Role;
use Sipwise::Base;

use JSON qw();
use JSON::Pointer;
use JSON::Types qw(bool);
use HTTP::Status qw(:constants);
use Safe::Isa qw($_isa);
use Try::Tiny;
use DateTime::Format::HTTP qw();
use DateTime::Format::RFC3339 qw();
use Types::Standard qw(InstanceOf);
use Regexp::Common qw(delimited); # $RE{delimited}
use HTTP::Headers::Util qw(split_header_words);
use NGCP::Panel::Utils::ValidateJSON qw();

has('last_modified', is => 'rw', isa => InstanceOf['DateTime']);

sub get_valid_post_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};

    return unless $self->forbid_link_header($c);
    return unless $self->valid_media_type($c, $media_type);
    return unless $self->require_body($c);
    my $json =  $c->stash->{body};
    return unless $self->require_wellformed_json($c, $media_type, $json);

    return JSON::from_json($json);
}

sub get_valid_put_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};
    my $id = $params{id};

    return unless $self->valid_id($c, $id);
    return unless $self->forbid_link_header($c);
    return unless $self->valid_media_type($c, $media_type);
    return unless $self->require_body($c);
    my $json =  $c->stash->{body};
    return unless $self->require_wellformed_json($c, $media_type, $json);

    return JSON::from_json($json);
}

sub get_valid_patch_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};
    my $id = $params{id};

    return unless $self->valid_id($c, $id);
    return unless $self->forbid_link_header($c);
    return unless $self->valid_media_type($c, $media_type);
    return unless $self->require_body($c);
    my $json =  $c->stash->{body};
    return unless $self->require_wellformed_json($c, $media_type, $json);
    return unless $self->require_valid_patch($c, $json);

    return $json;
}

sub validate_form {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $resource = $params{resource};
    my $form = $params{form};
    my $run = $params{run} // 1;

    my @normalized = ();

    # move {xxx_id} into {xxx}{id} for FormHandler
    foreach my $key(keys %{ $resource } ) {
        if($key =~ /^(.+)_id$/ && $key ne "external_id") {
            $c->log->debug("++++++++++++ moving key $key with value " .  ($resource->{$key} // '<null>') . " to $1/id");
            push @normalized, $1;
            $resource->{$1}{id} = delete $resource->{$key};
        }
    }

    # remove unknown keys
    my %fields = map { $_->name => undef } $form->fields;
    for my $k (keys %{ $resource }) {
        unless(exists $fields{$k}) {
            $c->log->debug("+++++++++ deleting unknown key '$k' from message"); # TODO: user, message trace, ...
            delete $resource->{$k};
        }

        $resource->{$k} = DateTime::Format::RFC3339->format_datetime($resource->{$k})
            if $resource->{$k}->$_isa('DateTime');
        $resource->{$k} = $resource->{$k} + 0
            if(defined $resource->{$k} && (
               $form->field($k)->$_isa('HTML::FormHandler::Field::Integer') ||
               $form->field($k)->$_isa('HTML::FormHandler::Field::Money') ||
               $form->field($k)->$_isa('HTML::FormHandler::Field::Float')));

        # only do this for converting back from obj to hal
        # otherwise it breaks db fields with the \0 and \1 notation
        unless($run) {
            $resource->{$k} = JSON::Types::bool($resource->{$k})
                if(defined $resource->{$k} && 
                   $form->field($k)->$_isa('HTML::FormHandler::Field::Boolean'));
        }
    }

    if($run) {
        # check keys/vals
        $form->process(params => $resource, posted => 1);
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

sub error {
    my ($self, $c, $code, $message) = @_;

    $c->log->error("error $code - $message"); # TODO: user, trace etc
    
    $c->response->content_type('application/json');
    $c->response->status($code);
    $c->response->body(JSON::to_json({ code => $code, message => $message })."\n");
}

sub forbid_link_header {
    my ($self, $c) = @_;
    return 1 unless $c->request->header('Link');
    $self->error($c, HTTP_BAD_REQUEST, "The request must not contain 'Link' headers. Instead assert relationships in the entity body.");
    return;
}

sub valid_media_type {
    my ($self, $c, $media_type) = @_;
    return 1 if($c->request->header('Content-Type') && 
                index($c->request->header('Content-Type'), $media_type) == 0);
    $self->error($c, HTTP_UNSUPPORTED_MEDIA_TYPE, "Unsupported media type, accepting '$media_type' only.");
    return;
}

sub require_body {
    my ($self, $c) = @_;
    return 1 if length $c->stash->{body};
    $self->error($c, HTTP_BAD_REQUEST, "This request is missing a message body.");
    return;
}

sub require_precondition {
    my ($self, $c, $header_name) = @_;
    return 1 if $c->request->header($header_name);
    $self->error($c, HTTP_PRECONDITION_REQUIRED, "This request is required to be conditional, use the '$header_name' header.");
    return;
}

sub valid_precondition {
    my ($self, $c, $etag, $entity_name) = @_;
    my $if_match = $c->request->header('If-Match');
    return 1 if '*' eq $if_match || grep {$etag eq $_} Data::Record->new({
        split  => qr/\s*,\s*/, unless => $RE{delimited}{-delim => q(")},
    })->records($if_match);
    $self->error($c, HTTP_PRECONDITION_FAILED, "This '$entity_name' entity cannot be found, it is either expired or does not exist. Fetch a fresh one.");
    return;
}

sub require_preference {
    my ($self, $c) = @_;
    my @preference = grep { 'return' eq $_->[0] } split_header_words($c->request->header('Prefer'));
    return $preference[0][1]
        if 1 == @preference && ('minimal' eq $preference[0][1] || 'representation' eq $preference[0][1]);
    $self->error($c, HTTP_BAD_REQUEST, "This request is required to express an expectation about the response. Use the 'Prefer' header with either 'return=representation' or 'return='minimal' preference.");
    return;
}

sub require_wellformed_json {
    my ($self, $c, $media_type, $patch) = @_;
    try {
        NGCP::Panel::Utils::ValidateJSON->new($patch);
    } catch {
        $self->error($c, HTTP_BAD_REQUEST, "The entity is not a well-formed '$media_type' document. $_");
        return;
    };
    return 1;
}

=pod
# don't use caching for now, keep it as simple as possible
sub cached {
    my ($self, $c) = @_;
    my $response = $c->cache->get($c->request->uri->canonical->as_string);
    unless ($response) {
        $c->log->info('not cached');
        return;
    }
    my $matched_tag = $c->request->header('If-None-Match') && ('*' eq $c->request->header('If-None-Match'))
      || (grep {$response->header('ETag') eq $_} Data::Record->new({
        split => qr/\s*,\s*/, unless => $RE{delimited}{-delim => q(")},
      })->records($c->request->header('If-None-Match')));
    my $not_modified = $c->request->header('If-Modified-Since')
        && !($self->last_modified < DateTime::Format::HTTP->parse_datetime($c->request->header('If-Modified-Since')));
    if (
        $matched_tag && $not_modified
        || $matched_tag
        || $not_modified
    ) {
        $c->response->status(HTTP_NOT_MODIFIED);
        $c->response->headers($response->headers);
        $c->log->info('cached');
        return 1;
    }
    $c->log->info('stale');
    return;
}

sub etag {
    my ($self, $octets) = @_;
    return sprintf '"ni:/sha3-256;%s"', sha3_256_base64($octets);
}

sub expires {
    my ($self) = @_;
    return DateTime->now->clone->add(years => 1); # XXX insert product end-of-life
}
=cut

sub allowed_methods {
    my ($self) = @_;
    my $meta = $self->meta;
    my @allow;
    for my $method ($meta->get_method_list) {
        push @allow, $meta->get_method($method)->name
            if $meta->get_method($method)->can('attributes') && 'Allow' ~~ $meta->get_method($method)->attributes;
    }
    return [sort @allow];
}

sub valid_id {
    my ($self, $c, $id) = @_;
    return 1 if $id->is_integer;
    $self->error($c, HTTP_BAD_REQUEST, "Invalid id in request URI");
    return;
}

sub require_valid_patch {
    my ($self, $c, $json) = @_;

    my $valid_ops = { 
        'replace' => { 'path' => 1, 'value' => 1 },
        'copy' => { 'from' => 1, 'path' => 1 },
        # we don't support those, as they're quite useless in our case
        # TODO: maybe except for remove, which might set it to null?
        #'test' => { 'path' => 1, 'value' => 1 },
        #'move' => { 'from' => 1, 'path' => 1 },
        #'remove' => { 'path' => 1 },
        #'add' => { 'path' => 1, 'value' => 1 },
    };

    my $patch = JSON::from_json($json);
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
        my $tmpelem = { %{ $elem } };
        my $tmpops = { %{ $valid_ops } };
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

sub apply_patch {
    my ($self, $c, $entity, $json) = @_;
    my $patch = JSON::decode_json($json);
    for my $op (@{ $patch }) {
        my $coderef = JSON::Pointer->can($op->{op});
        die "invalid op '".$op->{op}."' despite schema validation" unless $coderef;
        try {
            for ($op->{op}) {
                if ('add' eq $_ or 'replace' eq $_) {
                    $entity = $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                } elsif ('remove' eq $_) {
                    $entity = $coderef->('JSON::Pointer', $entity, $op->{path});
                } elsif ('move' eq $_ or 'copy' eq $_) {
                    $entity = $coderef->('JSON::Pointer', $entity, $op->{from}, $op->{path});
                } elsif ('test' eq $_) {
                    die "test failed - path: $op->{path} value: $op->{value}\n"
                        unless $coderef->('JSON::Pointer', $entity, $op->{path}, $op->{value});
                }
            }
        } catch {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "The entity could not be processed: $_");
            return;
        };
    }
    return $entity;
}

sub set_body {
    my ($self, $c) = @_;
    $c->stash->{body} = $c->request->body ? (do { local $/; $c->request->body->getline }) : '';
}

sub log_request {
    my ($self, $c) = @_;

    my $params = join(', ', map { "'".$_."'='".($c->request->query_params->{$_} // '')."'" } 
        keys %{ $c->request->query_params }
    );
    my $user;
    if($c->user->roles eq "api_admin" || $c->user->roles eq "api_reseller") {
        $user = $c->user->login;
    } else {
        $user = $c->user->username . '@' . $c->user->domain;
    }

    $c->log->info("API function '".$c->request->path."' called by '" . $user . 
        "' ('" . $c->user->roles . "') from host '".$c->request->address."' with method '" . $c->request->method . "' and params " .
        (length $params ? $params : "''") .
        " and body '" . $c->stash->{body} . "'");
}

sub log_response {
    my ($self, $c) = @_;

    # TODO: should be put a UUID to stash in log_request and use it here to correlate
    # req/res lines?
    $c->forward(qw(Controller::Root render));
    $c->response->content_type('')
        if $c->response->content_type =~ qr'text/html'; # stupid RenderView getting in the way
    if (@{ $c->error }) {
        my $msg = join ', ', @{ $c->error };
        $c->log->error($msg);
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
        $c->clear_errors;
    }
    $c->log->info("API function '".$c->request->path."' generated response with code '" . 
        $c->response->code . "' and body '" .
        $c->response->body . "'");
}

1;
# vim: set tabstop=4 expandtab:
