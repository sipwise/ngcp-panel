use strict;
use warnings;

#use Test::More;
#use DateTime::Format::ISO8601 qw();
#use DateTime::TimeZone qw();
#use Time::HiRes qw(time);
#use Tie::IxHash;
use Config::General qw();

my $codebase = "/home/rkrenn/sipwise/git";

use lib "/home/rkrenn/sipwise/git/ngcp-schema/lib";
use lib "/home/rkrenn/sipwise/git/sipwise-base/lib";
use lib "/usr/local/devel/ngcp-schema/lib";
use lib "/usr/local/devel/sipwise-base/lib";
use NGCP::Schema qw();
use lib "/home/rkrenn/sipwise/git/ngcp-panel/lib";
use lib "/usr/local/devel/ngcp-panel/lib";
use NGCP::Panel::Utils::ProvisioningTemplates qw();

my @panel_configs = (
   '/home/rkrenn/sipwise/git/vagrant-ngcp/ngcp_panel.conf',
   '/usr/local/devel/vagrant-ngcp/ngcp_panel.conf',
);
my $template_name = 'vaa_test';

my %mock_objs = ();
my $c = _create_c();
my $templates = $c->config->{provisioning_templates};
$templates //= {};
map { $templates->{$_}->{name} = $_; } keys %$templates;
$c->stash->{'provisioning_template_name'} = $template_name;
$c->stash->{'provisioning_templates'} = $templates;

my $context = NGCP::Panel::Utils::ProvisioningTemplates::provision_begin(
    c => $c,
);
NGCP::Panel::Utils::ProvisioningTemplates::provision_commit_row(
    c => $c,
    context => $context,
    'values' => {
        service_number => '800010144',
        switch3_number => '19768988',
        company => "test12",
        purge => 1,
    }
);
NGCP::Panel::Utils::ProvisioningTemplates::provision_finish(
    c => $c,
    context => $context,
);

sub _create_c {

    my $config = _get_panel_config();

    {
        no strict "refs";  ## no critic (ProhibitNoStrict)
        *{'NGCP::Schema::set_transaction_isolation'} = sub {
            my ($self,$level) = @_;
            return $self->storage->dbh_do(
                sub {
                  my ($storage, $dbh, @args) = @_;
                  $dbh->do("SET TRANSACTION ISOLATION LEVEL " . $args[0]);
                },
                $level,
            );
        };
        *{'NGCP::Schema::set_wait_timeout'} = sub {
            my ($self,$timeout) = @_;
            return $self->storage->dbh_do(
                sub {
                  my ($storage, $dbh, @args) = @_;
                  $dbh->do("SET SESSION wait_timeout = " . $args[0]);
                },
                $timeout,
            );
        };
    }
    my $db = _get_schema();

    $c = _create_mock('c',
        _stash => {

        },
        stash => sub {
            my $self = shift;
            my $key = shift;
            return $self->{stash}->{$key} if $key;
            return $self->{stash};
        },
        _model => {
            DB => $db,
        },
        model => sub {
            my $self = shift;
            my $key = shift;
            return $self->{model}->{$key} if $key;
            return $self->{model};
        },
        log => sub {
            my $self = shift;
            return _create_mock('log',
                debug => sub {
                    my $self = shift;
                    my $str = shift;
                    my @params = @_;
                    print $str . "\n";
                },
                info => sub {
                    my $self = shift;
                    my $str = shift;
                    my @params = @_;
                    print $str . "\n";
                },
                error => sub {
                    my $self = shift;
                    my $str = shift;
                    my @params = @_;
                    print $str . "\n";
                },
            );
        },
        config => sub {
            my $self = shift;
            return $config;
        },
        user => sub {
            my $self = shift;
            return _create_mock('user',
                roles => sub {
                    my $self = shift;
                    return 'admin';
                },
                #webusername => sub {
                #    my $self = shift;
                #    return '$c->user->webusername';
                #},
                #domain => sub {
                #    my $self = shift;
                #    return _create_mock('_domain',
                #        domain => sub {
                #            my $self = shift;
                #            return '$c->user->domain->domain';
                #        },
                #    );
                #},
            );
        },
        request => sub {
            my $self = shift;
            return _create_mock('_request',
                _param => {
                #    '$c->request->params' => undef,
                },
                param => sub {
                    my $self = shift;
                    my $key = shift;
                    return $self->{param}->{$key} if $key;
                    return $self->{param};
                },
            );
        },

    );

}

sub _create_mock {
    my $class = shift;
    return $mock_objs{$class} if exists $mock_objs{$class};
    my %members = @_;
    my $obj = bless({},$class);
    foreach my $member (keys %members) {
        if ('CODE' eq ref $members{$member}) {
            no strict "refs";  ## no critic (ProhibitNoStrict)
            *{$class.'::'.$member} = $members{$member};
        } else {
            $obj->{substr($member,1)} = $members{$member};
        }
    }
    $mock_objs{$class} = $obj;
    return $obj;
}

sub _get_schema {

    my $schema = NGCP::Schema->connect({
        dsn                 => "DBI:mysql:database=provisioning;host=192.168.0.29;port=3306",
        user                => "root",
        #password            => "...",
        mysql_enable_utf8   => "1",
        on_connect_do       => "SET NAMES utf8mb4",
        quote_char          => "`",
    });
    $schema->set_wait_timeout(3600);

    return $schema;

}

sub _get_panel_config {

    my $config;
    foreach my $panel_config (@panel_configs) {
        if( -f $panel_config ){
            my $catalyst_config = Config::General->new($panel_config);
            my %config = $catalyst_config->getall();
            $config = \%config;
            last;
        }
    }
    return $config;

}
