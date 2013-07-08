package NGCP::Panel;
use Moose;
use namespace::autoclean;

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
/;
use Log::Log4perl::Catalyst qw();

extends 'Catalyst';

our $VERSION = '0.01';

# Configure the application.
#
# Note that settings in ngcp_panel.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with an external configuration file acting as an override for
# local deployment.

__PACKAGE__->config(
    name => 'NGCP::Panel',
    # Disable deprecated behavior needed by old applications
    disable_component_resolution_regex_fallback => 1,
    enable_catalyst_header => 1, # Send X-Catalyst header
    encoding => 'UTF-8',
    'View::HTML' => {
        INCLUDE_PATH => [
            __PACKAGE__->path_to('share', 'templates'),
            __PACKAGE__->path_to('share', 'layout'),
        ],
        ABSOLUTE => 1,
    },
    'View::JSON' => {
        #Set the stash keys to be exposed to a JSON response
        #(sEcho iTotalRecords iTotalDisplayRecords aaData) for datatables
        expose_stash    => [ qw(sEcho iTotalRecords iTotalDisplayRecords aaData) ],
    },

    'Plugin::Static::Simple' => {
        include_path => [
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
        default => {
            credential => {
                class => 'Password',
                password_field => 'password',
                password_type => 'clear'
            },
            store => {
                class => 'Minimal',
                users => {
                }
            }
        },
        subscriber => {
            credential => {
                class => 'Password',
                password_field => 'password',
                password_type => 'clear'
            },
            store => {
                class => 'Minimal',
                users => {
                    subscriberadmin => {
                        password => 'subscriberadmin',
                        roles => [qw/subscriberadmin subscriber/],
                    },
                    subscriber => {
                        password => 'subscriber',
                        roles => [qw/subscriber/],
                    },
                }
            }
        },
        reseller => {
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
            }
        },
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
            }
        }
    }
);
__PACKAGE__->config( default_view => 'HTML' );

__PACKAGE__->log(Log::Log4perl::Catalyst->new('ngcp_panel.conf'));

# Start the application
__PACKAGE__->setup();

=head1 NAME

NGCP::Panel - Catalyst based application

=head1 SYNOPSIS

    script/ngcp_panel_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<NGCP::Panel::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

# vim: set tabstop=4 expandtab:
