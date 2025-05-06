use strict;
use warnings;
use JE qw();
use Test::More;

my $je = JE->new();
my $je_result = $je->eval(<<EOJS
var f = function() {
    var ud = 'john\@doe.com';
    var i;
    var checksum = 0;
    var result = '';
    var packed = [ 0, 0x45, 0x80, ud.length ];
    for (i = 0; i < ud.length; i++) {
        packed.push(ud.charCodeAt(i));
    }
    for (i = 0; i < packed.length; i++) {
        checksum = checksum ^ packed[i];
    }
    packed.push(checksum);
    for (i = 0; i < packed.length; i++) {
        h = packed[i].toString(16);
        if (h.length < 2) {
            result = result + '0';
        }
        result = result + h;
    }
    return result.toUpperCase();
};
f();
EOJS
);
diag('js result: ' . $je_result);

my $ps = sub {
    #my $ud = $subscriber{username} . '@' . $domain{domain};
    my $ud = 'john@doe.com';
    my $packed = pack('CCC C a*', 0, 0x45, 0x80, length($ud), $ud);
    my $checksum = 0;
    for my $c (map {ord $_} split(//, $packed)) {
        $checksum ^= $c;
    }
    $packed .= pack('C', $checksum);
    return uc(unpack('H*', $packed));
};
my $ps_result = $ps->();
diag('perl result: ' . $ps_result);

is($je_result, $ps_result, 'result is the same');

done_testing();