package NGCP::Panel::Utils::LazyLoad;
use strict;
use warnings;

use NGCP::Panel::Utils::Generic qw(:all);

use Catalyst::Utils;
use File::Find::Rule;

sub path_to_module {
    my ($c, $path) = @_;

    my $ownfile = __FILE__;
    $ownfile =~ s/^\/?(.*?)\/?$/$1/;
    my @ownparts = split(/\//, $ownfile);
    pop @ownparts; pop @ownparts;

    $path =~ s/^\/?(.*?)\/?$/$1/;
    $c->log->error("++++ splitting path '$path'");
    my @parts = split(/\//, $path);
    if($parts[0] eq "api") {
        $parts[0] = "API";
    }

    # prepend base-dir for lazy controllers to path
    unshift @parts, ("Lazy", "Controller");
    unshift @parts, @ownparts;

    # if last part is an int, we assume it's an item, thus
    # pop the item id and append "item";
    use Data::Dumper;
    $c->log->error("++++ parts before item check: " . (Dumper \@parts));
    my $id;
    if(is_int($parts[-1])) {
        $id = pop @parts;
        $parts[-1] .= 'item';
    }
    $c->log->error("++++ parts after item check: " . (Dumper \@parts));
    my $name = pop @parts;
    $name .= '.pm';
   
    $path = join '/', @parts;

    $c->log->error("searching for '$name' in '$path' to lazy-load controller");

    #opendir(DIR, $path) or return;
    #my @files = readdir(DIR);
    #closedir(DIR);
    #foreach my $file(@files) {
    #    if($name =~ /^$file$/i) {
    #        $file =~ s/\//::/g;
    #        return "NGCP::Panel::LazyLoad::$file";
    #    }
    #}
    #return;

    my @files = File::Find::Rule
        ->file()
        ->name(qr/^$name$/i)
        ->maxdepth(1)
        ->in("/$path");


    my $file = shift @files;
    return unless($file);

    $c->log->error("found file '$file' to lazy-load");

    my $ownpath = '/' . join('/', @ownparts);
    $c->log->error("final ownpath is '$ownpath'");
    $file =~ s/^$ownpath\/?//g;
    $file =~ s/\//::/g;
    $file =~ s/\.pm//;
    return ["NGCP::Panel::$file", $id];
}

# derived from from Catalyst::setup_components
sub setup_component {
    my ($c, $component) = @_;

    Catalyst::Utils::ensure_class_loaded($component, { ignore_loaded => 1 } );
    $c->components->{$component} = $c->setup_component($component);
    $c->components->{$component}->register_actions($c);        
}

1;
