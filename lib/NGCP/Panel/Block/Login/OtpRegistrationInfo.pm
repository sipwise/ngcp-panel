package NGCP::Panel::Block::Login::OtpRegistrationInfo;

use warnings;
use strict;

use parent ("NGCP::Panel::Block::Block");

sub template {
    my $self = shift;
    return 'login/otp_registration_info.tt';
}

1;
