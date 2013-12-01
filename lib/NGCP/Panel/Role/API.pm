package NGCP::Panel::Role::API;
use Moose::Role;
use Sipwise::Base;

use JSON qw();
use HTTP::Status qw(:constants);
use Safe::Isa qw($_isa);
use Try::Tiny;

sub get_valid_post_data {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $media_type = $params{media_type};

    return unless $self->forbid_link_header($c);
    return unless $self->valid_media_type($c, $media_type);
    return unless $self->require_body($c);
    my $json =  do { local $/; $c->request->body->getline }; # slurp
    return unless $self->require_wellformed_json($c, $media_type, $json);

    return JSON::from_json($json);
}

sub validate_form {
    my ($self, %params) = @_;

    my $c = $params{c};
    my $resource = $params{resource};
    my $form = $params{form};

    my @normalized = ();

    # move {xxx_id} into {xxx}{id} for FormHandler
    foreach my $key(keys %{ $resource } ) {
        if($key =~ /^([a-z]+)_id$/) {
            push @normalized, $1;
            $resource->{$1}{id} = delete $resource->{$key};
        }
    }

    use Data::Printer; p $resource;

    # remove unknown keys
    my %fields = map { $_->name => undef } $form->fields;
    for my $k (keys %{ $resource }) {
        unless(exists $fields{$k}) {
            $c->log->info("deleting unknown key '$k' from message"); # TODO: user, message trace, ...
            delete $resource->{$k};
        }
        $resource->{$k} = DateTime::Format::RFC3339->format_datetime($resource->{$k})
            if $resource->{$k}->$_isa('DateTime');
    }

    # check keys/vals
    my $result = $form->run(params => $resource);
    if ($result->error_results->size) {
        my $e = $result->error_results->map(sub {
            sprintf 'field=\'%s\', input=\'%s\', errors=\'%s\'', $_->name, $_->input // '', $_->errors->join(q())
        })->join("; ");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Validation failed. $e");
        return;
    }

    # move {xxx}{id} back into {xxx_id} for DB
    foreach my $key(@normalized) {
        $resource->{$key . '_id'} = $resource->{$key}{id};
        delete $resource->{$key};
    }

    return 1;
}

# private

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
    return 1 if $c->request->body;
    $self->error($c, HTTP_BAD_REQUEST, "This request is missing a message body.");
    return;
}

sub require_wellformed_json {
    my ($self, $c, $media_type, $patch) = @_;
    try {
        NGCP::Panel::ValidateJSON->new($patch);
    } catch {
        $self->error($c, HTTP_BAD_REQUEST, "The entity is not a well-formed '$media_type' document. $_");
        return;
    };
    return 1;
}



1;
# vim: set tabstop=4 expandtab:
