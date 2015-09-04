use lib 'inc';
use Local::Module::Build;

my $builder = Local::Module::Build->new(
    module_name         => 'NGCP::Panel',
    license             => 'perl',
    dist_version_from   => 'lib/NGCP/Panel.pm',
    dist_abstract       => 'Sipwise Configuration Panel',
    tap_harness_args    => {
        timer           => 1,
        formatter_class => 'TAP::Formatter::JUnit',
        merge           => 1,
    },
    configure_requires => {
        'lib' => 0,
        'Module::Build' => '0.4004',
        'Moose' => 2,
    },
    add_to_cleanup => [ 'NGCP-Panel-*' ],
);
$builder->create_build_script;

__END__

=encoding UTF-8

=head1 NGCP-Panel

A completely overhauled provisioning interface for the NGCP system.

=head1 NAME

Build.PL - NGCP-Panel build system including test fixtures

=head1 SYNOPSIS

    perl ./Build
    ./Build test --webdriver='phantomjs --webdriver=4444'
    ./Build test --webdriver='java -jar selenium-server-standalone.jar'
    ./Build test --webdriver='chromedriver --url-base=wd/hub --port=4444'
    ./Build test --webdriver=selenium-rc # from CPAN distro Alien-SeleniumRC
    ./Build test --webdriver=external --wd-server=127.0.0.1:5555

    ./Build testcover --webdriver='phantomjs --webdriver=4444'
    ./Build test_api
    ./Build test_api --schema-base-dir=path/to/schema --server=https://1.2.3.4:1443

=head2 Options

    --mysqld-port     port where the mysqld should be started
    --mysql-dump      one or more mysql dumps to be imported to our mysqld
    --no-junit        don't output junit but normal TAP, for manual testing
    --run-server      panel should be started by build script
    --schema-base-dir directory of NGCP::Schema if its not yet installed
    --server          URI for socket test server
    --webdriver       Command to be run as Webdriver
    --wd-server       HOST:PORT of an external webdriver to connect to
    --help            brief help message
    --man             full documentation

=head1 OPTIONS

=head2 C<--mysqld-port>

If this option and C<--mysqld-dir> are supplied, a mysqld will be started
at the specified port and be used for the tests. mysqld will be stopped
and the temporary data deleted when this script finishes.

=head2 C<--mysql-dump>

If this option and C<--mysqld-port> are supplied, a mysqld will be started
and be used for the tests. It will import all dumps supplied with this option.
This option can be set multiple times. In this case all specified files will
be dumped into the database.

=head2 C<--run-server>

Does not take an argument. Indicates the ./Build script should start a
server running the panel by itself on the Address given by the --server
argument.

=head2 C<--schema-base-dir>

If the NGCP::Schema is not installed to a known path to perl, this
option can specify the base directory of its development location.
It will then be included via blib, so we have access to its lib and share.

=head2 C<--server>

URI for the HTTP::Server::PSGI socket server run for testing,
default C<http://localhost:5000>

=head2 C<--webdriver>

command to launch a webdriver
external if the webdriver is launched externally
this command is no longer required

=head2 C<--wd-server>

Host:Port of the webdriver to which the tests should connect.
Default is set by Test::WebDriver to localhost:4444

=head2 C<--help>

Print a brief help message and exits.

=head2 C<--man>

Prints the manual page and exits.

=head1 I18N

1. Update strings from database

    script/ngcp_panel_dump_db_strings.pl

2. regenerate messages.pot (use -v for verbose output)

    xgettext.pl --output=lib/NGCP/Panel/I18N/messages.pot --directory=lib/ --directory=share/templates/ --directory=share/layout -P perl=tt,pm

3. Update or create $LANG.po files

    msgmerge --update $LANG.po messages.pot

In case your language did not exist already:

    msginit --input=lib/NGCP/Panel/I18N/messages.pot --output=lib/NGCP/Panel/I18N/$LANG.po --locale=$LANG

