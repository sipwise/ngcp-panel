#!/usr/bin/perl -w
use strict;
use Sipwise::Base;
use Data::Printer;
use NGCP::Panel::Form::BillingFee;

sub field_to_json {
	my $name = shift;

	given($name) {
		when(/Float|Integer|Money|PosInteger|Minute|Hour|MonthDay|Year/) {
			return "Number";
		}
		when(/Boolean/) {
			return "Boolean";
		}
		when(/Repeatable/) {
			return "Array";
		}
		default {
			return "String";
		}
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
