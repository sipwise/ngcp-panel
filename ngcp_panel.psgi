use strict;
use warnings;

use NGCP::Panel;

my $app = NGCP::Panel->apply_default_middlewares(NGCP::Panel->psgi_app);
$app;

