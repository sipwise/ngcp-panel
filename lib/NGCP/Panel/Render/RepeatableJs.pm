package NGCP::Panel::Render::RepeatableJs;
# ABSTRACT: role providing method to construct repeatable javascript
use Moose::Role;

use JSON ('encode_json');


sub render_repeatable_js {
    my $self = shift;
    return '' unless $self->has_for_js;

    my $for_js = $self->for_js;
    my %index;
    my %html;
    my %level;
    use Data::Printer;
    my %add_map = ();
    my %rep_map = ();
    foreach my $f($self->fields) {
        # TODO: rather use $f->isa?
        p $f;
        if((ref $f) =~ /^HTML::FormHandler::Field::AddElement::/) {
            print "+++++++++++++++++ a=" . $f->accessor . ", r=" . $f->repeatable . "\n";
            $add_map{$f->accessor} = $f->repeatable; 
            $rep_map{$f->repeatable} = $f->accessor;
        } elsif((ref $f) =~ /^HTML::FormHandler::Field::Repeatable::/) {
            foreach my $f($f->fields) {
                if((ref $f) =~ /^HTML::FormHandler::Field::AddElement::/) {
                    print "2 +++++++++++++++++ a=" . $f->accessor . ", r=" . $f->repeatable . "\n";
                    $add_map{$f->accessor} = $f->repeatable; 
                    $rep_map{$f->repeatable} = $f->accessor;
                }
            }
        }
    }
    p %add_map;
    p %rep_map;
    my $add_map_str = encode_json(\%add_map);
    my $rep_map_str = encode_json(\%rep_map);
    foreach my $key ( keys %$for_js ) {
        $index{$key} = $for_js->{$key}->{index};
        $html{$key} = $for_js->{$key}->{html};
        $level{$key} = $for_js->{$key}->{level};
    }
    my $index_str = encode_json( \%index );
    my %encoded_html;
    use HTML::Entities;
    while (my ($k,$v) = each %html ) {
        $encoded_html{$k} = encode_entities($v);
    }
    my $html_str = encode_json( \%encoded_html );
    my $level_str = encode_json( \%level );
    my $js = <<EOS;
<script>
\$(document).ready(function() {
  var add_map = $add_map_str;
  var rep_map = $rep_map_str;
  var rep_index = $index_str;
  var rep_html_enc = $html_str;
  var rep_html = {};
  for(var k in rep_html_enc) {
    rep_html[k] = \$('<textarea/>').html(rep_html_enc[k]).text();  
  }
  console.log(rep_html);
  var rep_level = $level_str;
  \$('.add_element').click(on_add_element);
  function on_add_element() {
    // get the repeatable id
    var data_rep_id = \$(this).attr('data-rep-id');
    var add_id = rep_map[data_rep_id];

    var id_re = new RegExp('\.[0-9]+\.');
    var data_rep_id_0 = data_rep_id.replace(id_re, '.0.');
    

    // create a regex out of index placeholder
    var level = rep_level[data_rep_id_0]
    var re = new RegExp('\{index-' + level + '\}',"g");
    // replace the placeholder in the html with the index
    var index = rep_index[data_rep_id];
    if(index == undefined) index = 1;
    var html = rep_html[data_rep_id_0];

    var esc_rep_id = data_rep_id.replace(/[.]/g, '\\\\.');
    var esc_rep_id_0 = data_rep_id_0.replace(/[.]/g, '\\\\.');

    id_re = new RegExp(esc_rep_id_0, "g");
    html = html.replace(id_re, data_rep_id);

    html = html.replace(re, index);
    // escape dots in element id
    // append new element in the 'controls' div of the repeatable
    var rep_controls = \$('#' + esc_rep_id + ' > .controls');
    rep_controls.append(html);
    // increment index of repeatable fields
    index++;
    rep_index[data_rep_id] = index;
    //\$('.add_element').click(on_add_element);

    // initiate callback if there is a handler for that
    if(typeof repeatadd_handler !== "undefined" && repeatadd_handler != null) {
    	repeatadd_handler.onAdd(index-1);
    }
  }

  \$(document).on('click', '.rm_element', function() {
    var id = \$(this).attr('data-rep-elem-id');
    var esc_id = id.replace(/[.]/g, '\\\\.');
    var rm_elem = \$('#' + esc_id);
    rm_elem.remove();

    // initiate callback if there is a handler for that
    if(repeatadd_handler) {
    	var idx_id = id.replace(/^.+\\.(\\d+)\$/, "\$1");
    	repeatadd_handler.onRm(idx_id);
    }

    event.preventDefault();
  });

});
</script>
EOS
    return $js;
}


1;

__END__
=pod

=head1 NAME

HTML::FormHandler::Render::RepeatableJs - role providing method to construct repeatable javascript

=head1 VERSION

version 0.40026

=head1 SYNOPSIS

Creates jQuery javascript to add and delete repeatable
elements.

Note: This is still EXPERIMENTAL.
This is an EXAMPLE.
Changes are very likely to occur.
Javascript is not guaranteed to be best practice.
It will not work on all rendered repeatables (requires wrapper with id).
It is strongly suggested that you make your own role if you use it.
Then you can modify it as needed.
Or just write out the rep_ data to javascript variables, and write the
function in javascript.
This function uses a plain javascript confirmation dialog.
You almost certainly want to do something else.
This javascript depends on the Repeatable field having a 'controls' div class
in order to position the new elements. Use the Bootstrap wrapper or the
'controls_div' tag on the Simple wrapper.

A role to be used in a Form Class:

    package MyApp::Form::Test;
    use HTML::FormHandler::Moose;
    extends 'HTML::FormHandler';
    with 'HTML::FormHandler::Render::RepeatableJs';
    ...

=head2 DESCRIPTION

This contains one method, 'render_repeatable_js'. It's designed to be
used in a template, something like:

    [% WRAPPER "wrapper.tt" %]
    [% form.render_repeatable_js %]
    <h1>Editing Object .... </h1>
    [% form.render %]
    [% END -%]

It will render javascript which can be used with the AddElement field,
and setting the 'setup_for_js' flag in the Repeatable field to add
the ability to dynamically add a new repeatable element in a form.

Note: this code is provided as an example. You may need to write your
own javascript function if your situation is different.

Some of the extra information (level) in this function is in preparation for
handling nested repeatables, but it's not supported yet.

This function operates on HTML elements that have the id of the
repeatable element. That requires that the wrapper have the repeatable
instance ID (now rendered by default). If you don't have wrappers around
your repeatable elements, this won't work.

See L<HTML::FormHandler::Field::AddElement> for an example of rendering
an HTML element that can be used to provide the AddElement button.
See that field for the requirements for the add HTML.

See L<HTML::FormHandler::Field::RmElement> for an example of rendering
an HTML element that can be used to provide a 'remove' button.
See that field for the requirements for the remove HTML.

=head1 NAME

HTML::FormHandler::Render::RepeatableJs

=head1 AUTHOR

FormHandler Contributors - see HTML::FormHandler

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Gerda Shank.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

