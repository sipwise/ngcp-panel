#!/usr/bin/perl

use strict;
use warnings;

use Time::Period;
use DateTime;

    # original period, timeshift in "h:m", expected result (new period)
my $testcases = [
    [
        'yr {2010}',
        '+02:00',
        'yr {2010} yd {1} hr {2-23}, yr {2010} yd {2-366}, yr {2011} yd {1} hr {0-1}'
    ], [
        'yr {2010-2011}',
        '+02:00',
        'yr {2010} yd {1} hr {2-23}, yr {2010} yd {2-366}, yr {2011}, yr {2012} yd {1} hr {0-1}'
    ], [
        'wd {sa-su}',
        '+02:00',
        'wd {sa} hr {2-23}, wd {su}, wd {mo} hr {0-1}'
    ], [
        'yr {2010} wd {mo-fr}',
        '+02:00',
        'yr {2010} wd {mo} hr {2-23}, yr {2010} wd {tu-fr}, yr {2010} wd {sa} hr {0-1}, yr {2011} yd {1} wd{tu-sa} hr {0-1}'
    ],
];

my $sample_dates = [
    DateTime->new(
        year       => 2010,
        month      => 0,
        day        => 0,
        hour       => 0,
        minute     => 0,
        second     => 0,
    ),
    DateTime->new(
        year       => 2010,
        month      => 0,
        day        => 0,
        hour       => 0,
        minute     => 0,
        second     => 0,
    ),
    DateTime->new(
        year       => 2010,
        month      => 0,
        day        => 0,
        hour       => 0,
        minute     => 0,
        second     => 0,
    ),
    DateTime->new(
        year       => 2010,
        month      => 0,
        day        => 0,
        hour       => 0,
        minute     => 0,
        second     => 0,
    ),
    DateTime->new(
        year       => 2010,
        month      => 0,
        day        => 0,
        hour       => 0,
        minute     => 0,
        second     => 0,
    ),
];


1;