package NGCP::Panel::Controller::API::CustomerPreferenceDefs;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
use JSON::Types qw();
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API';

class_has('resource_name', is => 'ro', default => 'customerpreferencedefs');
class_has('dispatch_path', is => 'ro', default => '/api/customerpreferencedefs/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-customerpreferencedefs');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub GET :Allow {
    my ($self, $c) = @_;
    {
        my @links;
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf('%s', $self->dispatch_path));

        my $hal = Data::HAL->new(
            links => [@links],
        );

        my $preferences = $c->model('DB')->resultset('voip_preferences')->search({
            internal => 0,
            contract_pref => 1,
        });
        my $resource = {};
        for my $pref($preferences->all) {
            my $fields = { $pref->get_inflated_columns };
            # remove internal fields
            for my $del(qw/type attribute expose_to_customer internal peer_pref usr_pref dom_pref contract_pref voip_preference_groups_id id modify_timestamp/) {
                delete $fields->{$del};
            }
            $fields->{max_occur} = int($fields->{max_occur});
            $fields->{read_only} = JSON::Types::bool($fields->{read_only});
            if($fields->{data_type} eq "enum") {
                my @enums = $pref->voip_preferences_enums->search({
                    contract_pref => 1,
                })->all;
                $fields->{enum_values} = [];
                foreach my $enum(@enums) {
                    my $efields = { $enum->get_inflated_columns };
                    for my $del(qw/id preference_id usr_pref dom_pref peer_pref contract_pref/) {
                        delete $efields->{$del};
                    }
                    $efields->{default_val} = JSON::Types::bool($efields->{default_val});
                    push @{ $fields->{enum_values} }, $efields;
                }
            }
            $resource->{$pref->attribute} = $fields;
        }
        $hal->resource($resource);

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
    my $allowed_methods = $self->allowed_methods;
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
