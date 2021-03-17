[![Crowdin](https://badges.crowdin.net/ngcp-panel/localized.svg)](https://crowdin.com/project/ngcp-panel)

# NGCP-Panel

A completely overhauled provisioning interface for the NGCP system.

# NAME

Build.PL - NGCP-Panel build system including test fixtures

# SYNOPSIS

Usage:

```
$ perl ./Build
$ ./Build test --webdriver='phantomjs --webdriver=4444'
$ ./Build test --webdriver='java -jar selenium-server-standalone.jar'
$ ./Build test --webdriver='chromedriver --url-base=wd/hub --port=4444'
$ ./Build test --webdriver=selenium-rc # from CPAN distro Alien-SeleniumRC
$ ./Build test --webdriver=external --wd-server=127.0.0.1:5555
```

```
$ ./Build test_tap --webdriver=external # outputs tap to tap/ folder
```

```
$ ./Build testcover --webdriver='phantomjs --webdriver=4444'
```

# OPTIONS

`--webdriver` _COMMAND_
:   (required) _COMMAND_ to launch a webdriver external if the webdriver is
    launched externally

`--wd-server` _HOST_:_PORT_
:   _HOST_:_PORT_ of the webdriver to which the tests should connect. Default
    is set by `Test::WebDriver` to **localhost:4444**.

`--server` _URI_
:   _URI_ for the `HTTP::Server::PSGI` socket server run for testing, default
    **http://localhost:5000**.

`--schema-base-dir` _DIR_
:   If the `NGCP::Schema` is not installed to a known path to perl, this
    option can specify the base _DIR_ of its development location. It
    will then be included via `blib`, so we have access to its lib and share.

`--mysqld-port` _PORT_
:   If this option and `--mysqld-dir` are supplied, a `mysqld` will be started
    at the specified _PORT_ and be used for the tests. `mysqld` will be stopped
    and the temporary data deleted when this script finishes.

`--mysql-dump`
:   If this option and `--mysqld-port` are supplied, a `mysqld` will be
    started and be used for the tests. It will import all dumps supplied
    with this option. This option can be set multiple times. In this case
    all specified files will be dumped into the database.

`--help`
:   Print a brief help message and exits.

`--man`
:   Prints the manual page and exits.

# I18N

Update strings from database:

```
$ script/ngcp_panel_dump_db_strings.pl
```

Regenerate messages.pot (use -v for verbose output):

```
$ xgettext.pl --output=lib/NGCP/Panel/I18N/messages.pot --directory=lib/ --directory=share/templates/ --directory=share/layout -P perl=tt,pm
```

In case your language does not exist already:

```
$ msginit --input=lib/NGCP/Panel/I18N/messages.pot --output=lib/NGCP/Panel/I18N/$LANG.po --locale=$LANG
```

Update or create $LANG.po files:

```
$ msgmerge --update $LANG.po messages.pot
```
