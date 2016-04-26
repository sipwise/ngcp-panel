package NGCP::Panel::Controller::API::MetaConfigDefs;
use NGCP::Panel::Utils::Generic qw(:all);
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Preferences;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
use JSON::Types qw();
use Config::General;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use base qw/Catalyst::Controller NGCP::Panel::Role::API/;

sub resource_name{
    return 'metaconfigdefs';
}
sub dispatch_path{
    return '/api/metaconfigdefs/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-metaconfigdefs';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],#left adminand reseller, as test can run as reseller too. Just don't return full config
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
        
        #my $resource = $c->config;
        my $catalyst_config = Config::General->new($c->config->{'Plugin::ConfigLoader'}->{file});   
        my %config_internal = $catalyst_config->getall();
        my %config;
        
        $config{file} = $c->config->{'Plugin::ConfigLoader'}->{file};
        $config{numbermanagement}->{auto_sync_cli} = $config_internal{numbermanagement}->{auto_sync_cli};
        $config{numbermanagement}->{auto_allow_cli} = $config_internal{numbermanagement}->{auto_allow_cli};
        $config{features} = $config_internal{features};
        
        my $meta = {
            collections => {
                #name => {
                    #module => '',
                    #allowed_methods => [],
                    #module_item =>''
                    #allowed_methods_item => [],
                    #query_params => [],
                    #allowed_roles => [],
                    #container_item_id => '',
                    #unique_fields => [['table.field','table1.fields1']],
                #}
            },
        };
        (my($files,$modules,$collections)) = NGCP::Panel::Utils::API::get_collections('NGCP::Panel::Controller::API::MetaConfigDefs');

        for ( my $i=0; $i < $#$collections; $i++)
        {
            my $collection = $collections->[$i];
            my $module = $modules->[$i];
            my $module_item = $module.'Item';
            my $roles = $module->can('config') ? $module->config->{action}->{OPTIONS}->{AllowedRole}:[];
            (!(ref $roles eq 'ARRAY')) and $roles = [$roles];
            $meta->{collections}->{$collection} = {
                module => $module,
                allowed_methods => $module->can('config') ? $module->config->{action} : {},
                query_params => $module->can('query_params') ? [map {$_->{param}} @{$module->query_params}] : [],
                allowed_roles => [$roles],
                module_item => $module_item->can('config') ? $module_item : '',
                allowed_methods_item => $module_item->can('config') ? $module_item->config->{action} : {},
                #container_item_id => '',
                #unique_fields => [['table.field','table1.fields1']],
            };
        }
    
        
        my $resource = { config => \%config, meta => $meta };
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
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
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

no Moose;
1;

# vim: set tabstop=4 expandtab:
