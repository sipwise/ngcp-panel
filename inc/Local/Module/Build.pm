package Local::Module::Build;
use Sipwise::Base;
use Moose qw(around);
extends 'Module::Build';

our ($plackup, $webdriver, @cover_opt);

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
            if $timer > 30;
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

around('ACTION_test', sub {
    my $super = shift;
    my $self = shift;

    require Getopt::Long;
    my %opt = (server => 'http://localhost:5000');
    Getopt::Long::GetOptions(\%opt, 'webdriver=s', 'server:s', 'help|?', 'man')
        or die 'could not process command-line options';

    require Pod::Usage;
    Pod::Usage::pod2usage(-exitval => 1, -input => 'Build.PL') if $opt{help};
    Pod::Usage::pod2usage(-exitval => 0, -input => 'Build.PL', -verbose => 2) if $opt{man};
    Pod::Usage::pod2usage("$0: --webdriver option required.\nRun `perldoc Build.PL`") unless $opt{webdriver};

    $webdriver = child { exec $opt{webdriver} };
    $self->wait_socket(qw(localhost 4444));

    require URI;
    my $uri = URI->new($opt{server});

    require File::Which;
    $plackup = child {
        exec $^X,
            '-Ilib',
            @cover_opt,
            File::Which::which('plackup'),
            sprintf('--listen=%s:%s', $uri->host, $uri->port),
            'ngcp_panel.psgi';
    };
    $self->wait_socket($uri->host, $uri->port);
    $ENV{CATALYST_SERVER} = $opt{server};
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

END { shutdown_servers }
