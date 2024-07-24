package Catalyst::Plugin::NGCP::License;
use warnings;
use strict;
use MRO::Compat;

use NGCP::Panel::Utils::Generic qw();

sub licenses {
    return NGCP::Panel::Utils::License::get_licenses(@_);
}

sub license {
    return NGCP::Panel::Utils::License::get_license(@_);
}

sub license_meta {
    return NGCP::Panel::Utils::License::get_license_meta(@_);
}

sub license_max_pbx_groups {
    return NGCP::Panel::Utils::License::get_max_pbx_groups(@_);
}

sub license_max_pbx_subscribers {
    return NGCP::Panel::Utils::License::get_max_pbx_subscribers(@_);
}

sub license_max_subscribers {
    return NGCP::Panel::Utils::License::get_max_subscribers(@_);
}

sub license_current_pbx_groups {
    return NGCP::Panel::Utils::License::get_current_pbx_groups(@_);
}

sub license_current_pbx_subscribers {
    return NGCP::Panel::Utils::License::get_current_pbx_subscribers(@_);
}

sub license_current_subscribers {
    return NGCP::Panel::Utils::License::get_current_subscribers(@_);
}

1;
