#!/usr/bin/perl -w
use strict;
use lib '../lib';

use NGCP::Panel::Form::SubscriberCFAdvanced;
use Data::Printer;

my $f = NGCP::Panel::Form::SubscriberCFAdvanced->new;
if($f->has_for_js) {
	print ">>>>>>>>>>>> js\n";
	p $f->render_repeatable_js;
}
print ">>>>>>>>>>>> form\n";
p $f->render;
