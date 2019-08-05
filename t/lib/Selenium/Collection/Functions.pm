package Selenium::Collection::Functions;

use warnings;
use strict;
use Moo;
use TryCatch;

use Selenium::Remote::Driver::FirefoxExtensions;
$Selenium::Remote::Driver::FORCE_WD3=1;

sub create_driver {
    my ($port) = @_;
    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome
    if ($port) {
        my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
            browser_name => $browsername,
            pageLoadStrategy => 'normal',
            extra_capabilities => {
                acceptInsecureCerts => \1,
            },
            port => $port
        );
        return $d;
    } else {
        try {
            my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
                browser_name => $browsername,
                pageLoadStrategy => 'normal',
                extra_capabilities => {
                    acceptInsecureCerts => \1,
                },
                port => '4444'
            );
            return $d;
        }
        try {
            my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
                browser_name => $browsername,
                pageLoadStrategy => 'normal',
                extra_capabilities => {
                    acceptInsecureCerts => \1,
                },
                port => '5555'
            );
            return $d;
        }
        try {
            my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
                browser_name => $browsername,
                pageLoadStrategy => 'normal',
                extra_capabilities => {
                    acceptInsecureCerts => \1,
                },
                port => '6666'
            );
            return $d;
        }
        try {
            my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
                browser_name => $browsername,
                pageLoadStrategy => 'normal',
                extra_capabilities => {
                    acceptInsecureCerts => \1,
                },
                port => '7777'
            );
            return $d;
        }
    };
    return;
}
1;
