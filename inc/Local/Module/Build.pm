package Local::Module::Build;
use Moose qw(around extends);
use TryCatch;
use LWP::UserAgent;
extends 'Module::Build';

sub _test_preconditions {
    my ($self) = @_;

    require Getopt::Long;
    Getopt::Long::Configure('pass_through');
    my %opt = (server => 'http://localhost:1443');
    Getopt::Long::GetOptions(\%opt, 
        'server:s',
        'help|?', 'man',
        'wd-server=s',
        'schema-base-dir=s',
        'no-junit',
            ) or die 'could not process command-line options';

    require Pod::Usage;
    Pod::Usage::pod2usage(-exitval => 1, -input => 'Build.PL') if $opt{help};
    Pod::Usage::pod2usage(-exitval => 0, -input => 'Build.PL', -verbose => 2) if $opt{man};

    if ($opt{'no-junit'}) {
        delete $self->tap_harness_args->{formatter_class};
        $self->tap_harness_args->{verbosity} = 1;
    }

    if ($opt{'wd-server'}) {
        my ($wd_host, $wd_port) = $opt{'wd-server'} =~ m{([^/:]+):([0-9]+)};
        $ENV{TWD_HOST} = $wd_host;
        $ENV{TWD_PORT} = $wd_port;
    }

    if ($opt{'schema-base-dir'}) {
        require blib;
        blib->import($opt{'schema-base-dir'});
    }

    $SIG{'INT'} = sub { exit(1) }; # for clean stopping of servers

    unless ($opt{server} =~ m|^https?://|) {
        die "Wrong format of server argument, should start with 'http(s)'.";
    }
    $opt{server} =~ s!/$!!;
    
    $ENV{CATALYST_SERVER} = $opt{server};
    if ($self->verbose) {
        print("Server is: ".$opt{server}."\n");
    }
}

sub _download_certs {
    my ($self) = @_;
    my $uri = $ENV{CATALYST_SERVER};
    use File::Temp qw/tempfile/;
    my ($ua, $req, $res);
    $ua = LWP::UserAgent->new(cookie_jar => {}, ssl_opts => {verify_hostname => 0});
    $res = $ua->post($uri.'/login/admin', {username => 'administrator', password => 'administrator'}, 'Referer' => $uri.'/login/admin');
    $res = $ua->get($uri.'/dashboard/');
    $res = $ua->get($uri.'/administrator/1/api_key');
    if ($res->decoded_content =~ m/gen\.generate/) { # key need to be generated first
        $res = $ua->post($uri.'/administrator/1/api_key', {'gen.generate' => 'foo'}, 'Referer' => $uri.'/dashboard');
    }
    my (undef, $tmp_apiclient_filename) = tempfile;
    my (undef, $tmp_apica_filename) = tempfile;
    $res = $ua->post($uri.'/administrator/1/api_key', {'pem.download' => 'foo'}, 'Referer' => $uri.'/dashboard', ':content_file' => $tmp_apiclient_filename);
    $res = $ua->post($uri.'/administrator/1/api_key', {'ca.download' => 'foo'}, 'Referer' => $uri.'/dashboard', ':content_file' => $tmp_apica_filename);
    $ENV{API_SSL_CLIENT_CERT} = $tmp_apiclient_filename;
    $ENV{API_SSL_CA_CERT} = $tmp_apica_filename;
    print "Client cert: $tmp_apiclient_filename - CA cert: $tmp_apica_filename\n" if $self->verbose;
}

around('ACTION_test', sub {
    my $super = shift;
    my $self = shift;

    $self->_test_preconditions;

    try {
        $self->$super(@_);
    };
});

sub ACTION_testcover {
    my ($self) = @_;
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
    my @cover_opt = (  # TODO: unused and unsusable currently
        '-Msigtrap "handler", sub { exit }, "normal-signals"',
        '-MDevel::Cover=+ignore,ngcp_panel.psgi,+ignore,plackup',
    );
    $self->depends_on('test');
    #shutdown_servers;
    sleep 5;
    $self->do_system(qw(cover));
}

sub ACTION_test_selenium {
    my ($self) = @_;
    $self->depends_on('code');
    $self->_test_preconditions;
    $self->test_files('t/selenium/*.t');
    $self->generic_test(type => 'default');
}

sub ACTION_test_api {
    my ($self) = @_;
    $self->depends_on('code');
    $self->_test_preconditions;
    $self->_download_certs;
    $self->test_files('t/api-rest/*.t');
    $self->generic_test(type => 'default');
    unlink ($ENV{API_SSL_CLIENT_CERT}, $ENV{API_SSL_CA_CERT}); # created by _download_certs()
}

sub ACTION_test_generic {
    my ($self) = @_;
    $self->depends_on('code');
    $self->_test_preconditions;
    $self->_download_certs;
    $self->generic_test(type => 'default');
    unlink ($ENV{API_SSL_CLIENT_CERT}, $ENV{API_SSL_CA_CERT}); # created by _download_certs()
}

sub ACTION_readme {
    require Pod::Readme;
    my $parser = Pod::Readme->new();
    $parser->parse_from_file('Build.PL', 'README');
}

1;
