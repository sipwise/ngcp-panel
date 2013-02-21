package NGCP::Panel::Widget;
use Moose;
use File::Find::Rule;

sub widgets {
    my ($self, $c, $filter) = @_;
    my $path = 
        $c->config->{home} . 
        '/lib/' . 
        $self->meta->name =~ s/::/\//rg ; 

    my @widget_files = File::Find::Rule
        ->file()
        ->name($filter)
        ->relative()
        ->in($path);

    my $widgets = [];
    foreach(@widget_files) {
        my $mpath = $path . '/' . $_;
        my $mname = $self->meta->name . '::' . s/\.pm$//r;
        require $mpath;
        push @{ $widgets }, $mname->new;
    }
    return $widgets;
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;
# vim: set tabstop=4 expandtab:
