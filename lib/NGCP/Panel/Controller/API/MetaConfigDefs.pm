package NGCP::Panel::Controller::API::MetaConfigDefs;
use NGCP::Panel::Utils::Generic qw(:all);
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::Preferences;
use JSON::Types qw();
use Config::General;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use base qw/NGCP::Panel::Role::API NGCP::Panel::Role::Entities/;

sub resource_name{
    return 'metaconfigdefs';
}

sub dispatch_path{
    return '/api/metaconfigdefs/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-metaconfigdefs';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

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
            $roles = 'ARRAY' eq ref $roles ? $roles : [$roles];
            $meta->{collections}->{$collection} = {
                module => $module,
                allowed_methods => $module->can('config') ? $module->config->{action} : {},
                query_params => $module->can('query_params') ? [map {$_->{param}} @{$module->query_params}] : [],
                allowed_roles => $roles,
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



no Moose;
1;

# vim: set tabstop=4 expandtab:
