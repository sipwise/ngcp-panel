#!/usr/bin/perl -w
use strict;
use Sipwise::Base;
use Data::Printer;
use NGCP::Panel::Form::BillingFee;

sub field_to_json {
	local $_ = shift;

	if (/Float|Integer|Money|PosInteger|Minute|Hour|MonthDay|Year/) {
		return "Number";
	} elsif (/Boolean/) {
		return "Boolean";
		}
	} elsif (/Repeatable/) {
		return "Array";
	} else {
		return "String";
	}
}

my $form = NGCP::Panel::Form::BillingFee->new;

foreach my $f($form->fields) {
	next if (
		$f->type eq "Hidden" ||
		$f->type eq "Button" ||
		$f->type eq "Submit" ||
		0);
	my @types = ();
	push @types, 'null' unless $f->required;
	push @types, field_to_json($f->type);

	print $f->name . " (" . join(', ', @types) . ")" . "\n";
}
