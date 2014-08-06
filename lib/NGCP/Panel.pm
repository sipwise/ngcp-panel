package NGCP::Panel;
use Moose;

use Catalyst::Runtime 5.80;

# Set flags and add plugins for the application.
#
# Note that ORDERING IS IMPORTANT here as plugins are initialized in order,
# therefore you almost certainly want to keep ConfigLoader at the head of the
# list if you're using it.
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
    ConfigLoader
    Static::Simple
    Authentication
    Authorization::Roles
    Session
    Session::Store::FastMmap
    Session::State::Cookie
    I18N
    Email
/;
#    EnableMiddleware
use Log::Log4perl::Catalyst qw();
#use NGCP::Panel::Cache::Serializer qw();
#use NGCP::Panel::Middleware::HSTS qw();
#use NGCP::Panel::Middleware::TEgzip qw();
extends 'Catalyst';

our $VERSION = '0.01';

my $panel_config;
for my $path(qw#/etc/ngcp-panel/ngcp_panel.conf etc/ngcp_panel.conf ngcp_panel.conf#) {
    if(-f $path) {
        $panel_config = $path;
        last;
    }
}
$panel_config //= 'ngcp_panel.conf';

my $logger_config = '/etc/ngcp-panel/logging.conf';
$logger_config = $panel_config unless(-f $logger_config);

__PACKAGE__->config(
    name => 'NGCP::Panel',
    # Disable deprecated behavior needed by old applications
    disable_component_resolution_regex_fallback => 1,
    enable_catalyst_header => 1, # Send X-Catalyst header
    encoding => 'UTF-8',
    'Plugin::ConfigLoader' => {
        file => $panel_config,
    },
    'View::HTML' => {
        INCLUDE_PATH => [
            '/usr/share/ngcp-panel/templates',
            '/usr/share/ngcp-panel/layout',
            '/usr/share/ngcp-panel/static',
            __PACKAGE__->path_to('share', 'templates'),
            __PACKAGE__->path_to('share', 'layout'),
            __PACKAGE__->path_to('share', 'static'),
        ],
        ABSOLUTE => 1,
        EVAL_PERL => 1,
    },
    'View::JSON' => {
        #Set the stash keys to be exposed to a JSON response
        #(sEcho iTotalRecords iTotalDisplayRecords aaData) for datatables
        expose_stash    => [ qw(sEcho iTotalRecords iTotalDisplayRecords aaData) ],
    },
    'View::TT' => {
        INCLUDE_PATH => [
            '/usr/share/ngcp-panel/templates',
            '/usr/share/ngcp-panel/layout',
            '/usr/share/ngcp-panel/static',
            __PACKAGE__->path_to('share', 'templates'),
            __PACKAGE__->path_to('share', 'layout'),
            __PACKAGE__->path_to('share', 'static'),
        ],
        ABSOLUTE => 1,
        EVAL_PERL => 1,
    },

    'Plugin::Static::Simple' => {
        include_path => [
            '/usr/share/ngcp-panel/static',
            __PACKAGE__->path_to('share', 'static'),
        ],
        mime_types => {
            woff => 'application/x-font-woff',
        },
    },

    session => {
        flash_to_stash => 1,
        expires => 3600,
    },

    'Plugin::Authentication' => {
        default_realm => 'subscriber',
        admin => {
            credential => {
                class => 'Password',
                password_field => 'md5pass',
                password_type => 'hashed',
                password_hash_type => 'MD5'
            },
            store => {
                class => 'DBIx::Class',
                user_model => 'DB::admins',
                id_field => 'id',
                store_user_class => 'NGCP::Panel::AuthenticationStore::RoleFromRealm',
                use_userdata_from_session => 1,
            }
        },
        api_admin_cert => {
            # TODO: should be NoPassword, but it's not available in our catalyst version yet
            credential => {
                class => 'Password',
                password_field => 'is_active',
                password_type => 'clear',
            },
            store => {
                class => 'DBIx::Class',
                user_model => 'DB::admins',
                id_field => 'id',
                store_user_class => 'NGCP::Panel::AuthenticationStore::RoleFromRealm',
            },
            use_session => 0,
        },
        api_admin_http => {
            credential => {
                class => 'HTTP',
                #type => 'digest',
                type => 'basic',
                username_field => 'login',
                password_field => 'md5pass',
                password_type => 'hashed',
                password_hash_type => 'MD5'
            },
            store => {
                class => 'DBIx::Class',
                user_model => 'DB::admins',
                id_field => 'id',
                store_user_class => 'NGCP::Panel::AuthenticationStore::RoleFromRealm',
            },
            use_session => 0,
        },
        subscriber => {
            credential => {
                class => 'Password',
                password_field => 'webpassword',
                password_type => 'clear',
            },
            store => {
                class => 'DBIx::Class',
                user_model => 'DB::provisioning_voip_subscribers',
                id_field => 'id',
                store_user_class => 'NGCP::Panel::AuthenticationStore::RoleFromRealm',
                use_userdata_from_session => 1,
            }
        }
    },
#    'Plugin::EnableMiddleware' => [
#        NGCP::Panel::Middleware::TEgzip->new,
#        NGCP::Panel::Middleware::HSTS->new,
#    ],
);
__PACKAGE__->config( default_view => 'HTML' );

__PACKAGE__->config( email => ['Sendmail'] );

__PACKAGE__->log(Log::Log4perl::Catalyst->new($logger_config));

# Start the application
__PACKAGE__->setup();

1;

# vim: set tabstop=4 expandtab:
