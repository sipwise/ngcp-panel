#!/usr/bin/perl -w
use lib '../lib';
#use lib '/home/agranig/projects/HTML-FormHandler-0.40026/lib';

use strict;
use Data::Printer;

{
    package MyApp::Form::Test;
    use HTML::FormHandler::Moose;
    extends 'HTML::FormHandler';
    with 'HTML::FormHandler::Render::RepeatableJs';
    #with 'HTML::FormHandler::Render::RepeatableJs';

    # Note: if using RepeatableJs, repeatable elements must be
    # wrapped in a 'controls' div (like the Bootstrap wrapper)
    #       set 'setup_for_js' flag
    #       do_wrapper is turned on by 'setup_for_js' flag
    has_field 'foo' => (
        type => 'Repeatable',
        setup_for_js => 1,
        do_wrapper => 1,
        tags => { controls_div => 1 },
    );

    # The 'remove' doesn't have to be a display field. It could be other html associated
    # with the repeatable element wrapper or label.
    has_field 'foo.remove' => (
        type => '+NGCP::Panel::Field::RmElement',
        value => 'Remove',
    );
    has_field 'foo.one';
    has_field 'foo.two';

    # 'AddElement' field is right after repeatable field
    # It also doesn't need to be a display field. Any way to get the correct HTML in is ok.
    # It requires the name of the repeatable (as accessed from AddElement parent)
    # The 'value' is the button text. See the AddElement field for requirements.
    has_field 'add_element' => (
        type => '+NGCP::Panel::Field::AddElement',
        repeatable => 'foo',
        value => 'Add another foo',
    );
    has_field 'bar';

}

my $form = MyApp::Form::Test->new;

print ">>>>>>>>>>>>>> render_repeatable_js\n";
p $form->render_repeatable_js;


print ">>>>>>>>>>>>>> render add_element\n";
p $form->field('add_element')->render;

print ">>>>>>>>>>>>>> render foo\n";
p $form->field('foo')->render;
