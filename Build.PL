use lib 'inc';
use Local::Module::Build qw();

my $builder = Local::Module::Build->new(
    module_name         => 'NGCP::Panel',
    license             => 'restrictive',
    dist_version_from   => 'lib/NGCP/Panel.pm',
    configure_requires => {
        'lib' => 0,
        'Module::Build' => '0.4004',
        'Moose' => 2,
        'Sipwise::Base' => 0,
    },
    requires => {
        'base' => 0,
        'Catalyst::Action::RenderView' => 0,
        'Catalyst::Model::DBIC::Schema' => 0,
        'Catalyst::Plugin::ConfigLoader' => 0,
        'Catalyst::Plugin::Static::Simple' => 0,
        'Catalyst::Plugin::Authentication' => 0,
        'Catalyst::Plugin::Authorization::Roles' => 0,
        'Catalyst::Plugin::Session' => 0,
        'Catalyst::Plugin::Session::Store::FastMmap' => 0,
        'Catalyst::Plugin::Session::State::Cookie' => 0,
        'Catalyst::Runtime' => '5.90014',
        'Catalyst::View::JSON' => 0,
        'Catalyst::View::TT' => 0,
        'Config::General' => 0,
        'HTML::FormHandler' => 0,
        'HTML::FormHandler::Field' => 0,
        'HTML::FormHandler::Field::Compound' => 0,
        'HTML::FormHandler::Field::Select' => 0,
        'HTML::FormHandler::Moose' => 0,
        'HTML::FormHandler::Widget::Block::Bootstrap' => 0,
        'Log::Log4perl::Catalyst' => 0,
        'Module::Runtime' => 0,
        'Moose' => 2,
        'Moose::Role' => 0,
        'Moose::Util::TypeConstraints' => 0,
        'MooseX::Object::Pluggable' => 0,
        'namespace::autoclean' => 0,
        'strict' => 0,
        'Template' => 0,
        'warnings' => 0,
        'Text::CSV_XS' => 0,
        'DBIx::Class::ResultSet::RecursiveUpdate' => 0.30,
        #patch to set foreign key instead of relation, install from github until its available on cpan
    },
    test_requires => {
        'Catalyst::Test' => 0,
        'File::Which' => 0,
        'Getopt::Long' => 0,
        'IO::Socket::IP' => 0,
        'JSON' => 0,
        'JSON::Parse' => 0,
        'lib' => 0,
        'Plack::Runner' => 0,
# actually, the `plackup` external bin. this will break if the Plack distro is split into pieces
        'Sipwise::Base' => 0,
        'Test::More' => 0,
        'Test::WebDriver' => 0,
        'strict' => 0,
        'Sys::Sig' => 0,
        'Test::WWW::Mechanize::Catalyst' => 0,
        'URI' => 0,
        'warnings' => 0,
    },
    recommends => {
        # for the testcover target
        'Devel::Cover' => 0,
        'sigtrap' => 0,
    },
    add_to_cleanup => [ 'NGCP-Panel-*' ],
);
$builder->create_build_script;

__END__

=encoding UTF-8

=head1 NAME

Build.PL - NGCP-Panel build system including test fixtures

=head1 SYNOPSIS

    perl ./Build
    ./Build test --webdriver='phantomjs --webdriver=4444'
    ./Build test --webdriver='java -jar selenium-server-standalone.jar'
    ./Build test --webdriver='chromedriver --port=4444'
    ./Build test --webdriver=selenium-rc # from CPAN distro Alien-SeleniumRC

    ./Build testcover --webdriver='phantomjs --webdriver=4444'

=head2 Options

    --webdriver     (required) external webdriver command
    --server        URI for socket test server
    --help          brief help message
    --man           full documentation

=head1 OPTIONS

=head2 C<--webdriver>

(required) command to launch a webdriver

=head2 C<--server>

URI for the HTTP::Server::PSGI socket server run for testing,
default C<http://localhost:5000>

=head2 C<--help>

Print a brief help message and exits.

=head2 C<--man>

Prints the manual page and exits.
