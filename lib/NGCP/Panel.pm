package NGCP::Panel;

use Moose;
use Catalyst::Runtime 5.80;
use File::Slurp qw();
use Config::General qw();
use IO::Socket::UNIX qw(SOCK_DGRAM);

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
    Session::Store::Redis
    Session::State::Cookie
    I18N
/;
use Log::Log4perl::Catalyst qw();
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

sub get_panel_config{
    my $config;
    if( -f $panel_config ){
        my $catalyst_config = Config::General->new($panel_config);
        my %config = $catalyst_config->getall();
        $config = \%config;
    }
    return $config;
}

my $logger_config;
for my $path(qw#./logging.conf /etc/ngcp-panel/logging.conf#) {
    if(-f $path) {
        $logger_config = $path;
        last;
    }
}
$logger_config = $panel_config unless(defined $logger_config);

for my $path(qw#./logging.conf /etc/ngcp-panel/logging.conf#) {
    if(-f $path) {
        $logger_config = $path;
        last;
    }
}
$logger_config = $panel_config unless(defined $logger_config);


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
            '/media/sf_/VMHost/ngcp-panel/share/templates',
            '/media/sf_/VMHost/ngcp-panel/share/layout',
            '/media/sf_/VMHost/ngcp-panel/share/static',
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
        expose_stash    => [ qw(sEcho iTotalRecords iTotalDisplayRecords iTotalRecordCountClipped iTotalDisplayRecordCountClipped aaData dt_custom_footer widget_data timeline_data) ],
    },
    'View::TT' => {
        INCLUDE_PATH => [
            '/media/sf_/VMHost/ngcp-panel/share/templates',
            '/media/sf_/VMHost/ngcp-panel/share/layout',
            '/media/sf_/VMHost/ngcp-panel/share/static',
            __PACKAGE__->path_to('share', 'templates'),
            __PACKAGE__->path_to('share', 'layout'),
            __PACKAGE__->path_to('share', 'static'),
        ],
        ABSOLUTE => 1,
        EVAL_PERL => 1,
    },

    'Plugin::Static::Simple' => {
        include_path => [
            '/media/sf_/VMHost/ngcp-panel/share/static',
            '/usr/share/ngcp-panel/static',
            __PACKAGE__->path_to('share', 'static'),
        ],
        mime_types => {
            woff => 'application/x-font-woff',
        },
    },

    'Plugin::Session' => {
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
                store_user_class => 'NGCP::Panel::Authentication::Store::RoleFromRealm',
                use_userdata_from_session => 1,
            }
        },
        admin_bcrypt => {
            credential => {
                class => 'Password',
                password_field => 'saltedpass',
                # we handle the salt and hash management manually in Login.pm
                password_type => 'clear',
            },
            store => {
                class => 'DBIx::Class',
                user_model => 'DB::admins',
                id_field => 'id',
                store_user_class => 'NGCP::Panel::Authentication::Store::RoleFromRealm',
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
                store_user_class => 'NGCP::Panel::Authentication::Store::RoleFromRealm',
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
                store_user_class => 'NGCP::Panel::Authentication::Store::RoleFromRealm',
            },
            use_session => 0,
        },
        api_subscriber_http => {
            credential => {
                class => 'HTTP',
                #type => 'digest',
                type => 'basic',
                username_field => 'webusername',
                password_field => 'webpassword',
                password_type => 'clear',
            },
            store => {
                class => 'DBIx::Class',
                user_model => 'DB::provisioning_voip_subscribers',
                store_user_class => 'NGCP::Panel::Authentication::Store::RoleFromRealm',
                # use_userdata_from_session => 1,
            },
            use_session => 0,
        },
        api_subscriber_jwt => {
            credential => {
                class => '+NGCP::Panel::Authentication::Credential::JWT',
                username_jwt => 'username',
                username_field => 'webusername',
                id_jwt => 'subscriber_uuid',
                id_field => 'uuid',
                jwt_key => _get_jwt_key(),
                debug => 1,
                alg => 'HS256',
            },
            store => {
                class => 'DBIx::Class',
                user_model => 'DB::provisioning_voip_subscribers',
                store_user_class => 'NGCP::Panel::Authentication::Store::RoleFromRealm',
            },
            use_session => 0,
        },
        api_admin_system => {
            credential => {
                class => 'HTTP',
                type => 'basic',
                username_field => 'login',
                password_field => 'password',
                password_type => 'clear',
            },
            store => {
                class => '+NGCP::Panel::Authentication::Store::System',
                file  => '/etc/default/ngcp-api',
                group => 'auth_system',
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
                store_user_class => 'NGCP::Panel::Authentication::Store::RoleFromRealm',
                use_userdata_from_session => 1,
            }
        }
    },
    ngcp_version => get_ngcp_version(),
);
__PACKAGE__->config( default_view => 'HTML' );

__PACKAGE__->log(Log::Log4perl::Catalyst->new($logger_config));

# configure Data::HAL depending on our config
{
    my $panel_config = get_panel_config;
    if ($panel_config->{appearance}{api_embedded_forcearray} || $panel_config->{appearance}{api_links_forcearray}) {
        require Data::HAL;
        *{Data::HAL::forcearray_policy} = sub {
            my ($self, $root, $property_type, $relation, $property) = @_;
            my $embedded = $root->embedded ? $root->embedded->[0] : undef;
            if ($embedded
                && ( (   $property_type eq 'links' &&  $panel_config->{appearance}{api_links_forcearray} )
                    || ( $property_type eq 'embedded' &&  $panel_config->{appearance}{api_embedded_forcearray}) )
                && $relation =~/^ngcp:[a-z0-9]+$/
            ) {
                return 1;
            }
            if (!$embedded
                && ( ( $property_type eq 'links' &&  $panel_config->{appearance}{api_links_forcearray} ) )
                && $relation =~/^ngcp:[a-z0-9]+$/
            ) {
                return 1;
            }
        };
    }
}

after setup_finalize => sub {

    my $app = shift;

    if ($ENV{NOTIFY_SOCKET}) {
        my $addr = $ENV{NOTIFY_SOCKET} =~ s/^@/\0/r;
        my $client = IO::Socket::UNIX->new(
            Type => SOCK_DGRAM(),
            Peer => $addr,
        ) or warn("can't connect to socket $ENV{NOTIFY_SOCKET}: $!\n");
        if ($client) {
            $client->autoflush(1);
            print $client "READY=1\n" or warn("can't send to socket $ENV{NOTIFY_SOCKET}: $!\n");
            close $client;
        }
    } else {
        warn("NOTIFY_SOCKET not set\n");
    }

};

# Start the application
__PACKAGE__->setup();

sub get_ngcp_version {
    my $content = File::Slurp::read_file("/etc/ngcp_version", err_mode => 'quiet');
    $content //= '(unavailable)';
    chomp($content);
    return $content;
}

sub _get_jwt_key {
    my $content = File::Slurp::read_file("/etc/ngcp-panel/jwt_secret", err_mode => 'quiet');
    $content //= '';
    $content =~ s/\n//; # remove newline before
    chomp($content);
    return $content;
}

1;

# vim: set tabstop=4 expandtab:
