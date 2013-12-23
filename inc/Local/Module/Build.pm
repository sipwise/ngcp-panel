package Local::Module::Build;
use Sipwise::Base;
use Moose qw(around);
use Child qw(child);
use Capture::Tiny qw(capture);
use TryCatch;
use MooseX::Method::Signatures;
extends 'Module::Build';

our ($plackup, $webdriver, @cover_opt, $mysqld);

method wait_socket($host, $port) {
    require IO::Socket::IP;
    my $timer = 0;
    while (1) {
        my $sock = IO::Socket::IP->new(
            PeerHost => $host,
            PeerPort => $port,
            Type     => IO::Socket::IP::SOCK_STREAM(),
        );
        last if $sock;
        sleep 1;
        $timer++;
        die sprintf('socket %s:%s is not accessible within 30 seconds after start', $host, $port)
            if $timer > 90;
    };
}

sub shutdown_servers {
    for my $proc ($webdriver, $plackup) {
        if ($proc) {
            require Sys::Sig;
            $proc->kill(Sys::Sig->TERM);
        }
    }
}

sub _test_preconditions {
    my ($self) = @_;

    require Getopt::Long;
    my %opt = (server => 'http://localhost:5000');
    Getopt::Long::GetOptions(\%opt, 'webdriver=s', 'server:s', 'help|?', 'man', 'wd-server=s', 'schema-base-dir=s', 'mysqld-port=s', 'mysql-dump=s@')
        or die 'could not process command-line options';

    require Pod::Usage;
    Pod::Usage::pod2usage(-exitval => 1, -input => 'Build.PL') if $opt{help};
    Pod::Usage::pod2usage(-exitval => 0, -input => 'Build.PL', -verbose => 2) if $opt{man};
    Pod::Usage::pod2usage("$0: --webdriver option required.\nRun `perldoc Build.PL`") unless $opt{webdriver};

    if ($opt{'wd-server'}) {
        my ($wd_host, $wd_port) = $opt{'wd-server'} =~ m{([^/:]+):([0-9]+)};
        $ENV{TWD_HOST} = $wd_host;
        $ENV{TWD_PORT} = $wd_port;
    }

    if ($opt{'schema-base-dir'}) {
        require blib;
        blib->import($opt{'schema-base-dir'})
    }

    $SIG{'INT'} = sub { exit(1) }; # for clean stopping of servers

    if ($opt{'mysqld-port'} && $opt{'mysql-dump'}) {
        require Test::mysqld;
        $mysqld = Test::mysqld->new(
            my_cnf => {
                'port' => $opt{'mysqld-port'},
            },
        ) or die "couldnt start mysqld";
        $ENV{NGCP_PANEL_CUSTOM_DSN} = $mysqld->dsn();
        my $dump_files = join(' ', @{ $opt{'mysql-dump'} });
        system("cat $dump_files | mysql -uroot --host=127.0.0.1 --port=$opt{'mysqld-port'}");
        system(qq/echo "GRANT ALL PRIVILEGES ON *.* TO 'sipwise'\@'localhost' WITH GRANT OPTION;" | mysql -uroot --host=127.0.0.1 --port=$opt{'mysqld-port'}/);
    }

    unless ($opt{webdriver} eq "external") {
        $webdriver = child { exec $opt{webdriver} };
        $self->wait_socket(qw(localhost 4444));
    }

    require URI;
    my $uri = URI->new($opt{server});

    require File::Which;
    $ENV{ NGCP_PANEL_CONFIG_LOCAL_SUFFIX } = "testing";
    $plackup = child {
        my $out_fh = IO::File->new("panel_debug_stdout", "w+");
        my $err_fh = IO::File->new("panel_debug_stderr", "w+");
        $out_fh->autoflush(1);
        $err_fh->autoflush(1);
        local $| = 1;
        capture {
        exec $^X,
            '-Ilib',
            exists $opt{'schema-base-dir'} ? "-Mblib=$opt{'schema-base-dir'}" : (),
            @cover_opt,
            scalar File::Which::which('plackup'),
            sprintf('--listen=%s:%s', $uri->host, $uri->port),
            'ngcp_panel.psgi';
        } stdout => $out_fh, stderr => $err_fh;
    };

    $self->wait_socket($uri->host, $uri->port);
    $ENV{CATALYST_SERVER} = $opt{server};
}

around('ACTION_test', sub {
    my $super = shift;
    my $self = shift;

    $self->_test_preconditions;

    try {
        $self->$super(@_);
    };
});

method ACTION_testcover {
    {
        my @missing;
        for my $module (qw(Devel::Cover sigtrap)) {
            push @missing, $module
                unless Module::Build::ModuleInfo->find_module_by_name($module);
        }
        if (@missing) {
            warn "modules required for testcover action: @missing\n";
            return;
        }
    }
    $self->add_to_cleanup('coverage', 'cover_db');
    $self->depends_on('code');
    $self->do_system(qw(cover -delete));
    @cover_opt = (
        '-Msigtrap "handler", sub { exit }, "normal-signals"',
        '-MDevel::Cover=+ignore,ngcp_panel.psgi,+ignore,plackup',
    );
    $self->depends_on('test');
    shutdown_servers;
    sleep 5;
    $self->do_system(qw(cover));
}

method ACTION_test_tap {
    $self->depends_on('code');
    $self->_test_preconditions;
    system( "mkdir -p tap" );
    $ENV{PERL_TEST_HARNESS_DUMP_TAP} = "tap/";
    $self->generic_test(type => 'default');
}

method ACTION_test_servers {
    $self->depends_on('code');
    $self->_test_preconditions;
    print "All servers ready for you!\nPress [Enter] to exit.";
    <STDIN>;
}

method ACTION_test_selenium {
    $self->depends_on('code');
    $self->_test_preconditions;
    $self->test_files('t/*_selenium.t t/admin-login.t');
    $self->generic_test(type => 'default');
}

method ACTION_readme {
    require Pod::Readme;
    my $parser = Pod::Readme->new();
    $parser->parse_from_file('Build.PL', 'README');
}

END { shutdown_servers }
