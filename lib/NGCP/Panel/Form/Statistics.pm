package NGCP::Panel::Form::Statistics;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid host folder select/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'host' => (
    type => 'Select',
    label => 'Host:',
    options_method => \&set_hosts,
    required => 1,
);

sub set_hosts {
    my($self) = @_;
    my @options = ();
    if(defined $self->form->ctx && 
       defined $self->form->ctx->stash->{hosts}) {
        my $hosts = $self->form->ctx->stash->{hosts};
        foreach my $h(@{ $hosts}) {
            push @options, { label => $h, value => $h };
        }
    }
    return \@options;
}

has_field 'folder' => (
    type => 'Select',
    label => 'Category:',
    options_method => \&set_folders,
    required => 1,
);

sub set_folders {
    my($self) = @_;
    my @options = ();
    if(defined $self->form->ctx && 
       defined $self->form->ctx->stash->{folders}) {
        my $folders = $self->form->ctx->stash->{folders};
        foreach my $f(@{ $folders }) {
            push @options, { label => $f, value => $f };
        }
    }
    return \@options;
}

has_field 'select' => (
    type => 'Submit',
    value => 'Select',
    element_class => [qw/btn btn-primary/],
    label => '',
);

1;
# vim: set tabstop=4 expandtab:
