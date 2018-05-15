#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

use NGCP::Panel::Form::CFSimpleAPI;

for(my $i=0; $i<200;$i++){
    my $form=NGCP::Panel::Form::CFSimpleAPI->new();
}
1;