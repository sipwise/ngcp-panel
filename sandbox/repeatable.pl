#!/usr/bin/perl -w
use strict;

{
	package MyForm;
	use HTML::FormHandler::Moose;
	extends 'HTML::FormHandler';
	 
	has_field 'args'      => (
		type => 'Repeatable',
		label => 'args_label',
	);
	has_field 'args.type' => (
		type => 'Text',
		label => 'args_type_label',
	);

	has_block 'fields' => (
		render_list => [qw(args)],
	);

	has_field 'save' => (
		type => 'Submit',
	);

	has_block 'actions' => (
		tag => 'div', 
		render_list => [qw(save)],
	);

	sub build_render_list {
		return [qw(fields actions)];
	}

	sub build_form_element_class {
		return [qw(form-horizontal)];
	}
}

use Data::Printer;

my $f = MyForm->new;
$f->process(params => {});
p $f->render;
