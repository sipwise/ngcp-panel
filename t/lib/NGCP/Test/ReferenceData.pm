package NGCP::Test::ReferenceData;
use strict;
use warnings;

use Moose;
use File::Basename;
use File::Slurp;
use File::Find::Rule;
use File::Path qw/make_path/;
use JSON qw/from_json to_json/;
use Data::Dumper;

has 'sid' => (
    isa => 'Maybe[Str]',
    is => 'rw',
    lazy => 1,
    default => sub { my $self = shift; $self->_test->generate_sid(); },

);

has 'use_persistent' => (
    isa => 'Int',
    is => 'rw',
    default => 1,
);

has 'persistent_path' => (
    isa => 'Str',
    is => 'rw',
    default => '/tmp',
);

has 'client' => (
    isa => 'Object',
    is => 'ro',
);

has 'ref_dir' => (
    is => 'rw',
    isa => 'Str',
    default => 'ReferenceData',
);

has 'depends' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub {[]},
);

has '_dependstree' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {{}},
);

has '_refdata' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub {[]},
);

has '_reftree' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {{}},
);

has '_refurls' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub {[]},
);

has 'delete_persistent' => (
    isa => 'Bool',
    is => 'rw',
    default => 0,
);

has '_test' => (
    isa => 'Object',
    is => 'ro',
);

sub BUILD {
    my ($self) = @_;

    my $ref_done = 0;
    unless(defined $self->sid) {
        $self->sid("".time);
    } else {
        if($self->use_persistent) {
            my $data_path = $self->persistent_path . "/" . $self->sid . "/refdata.json";
            my $tree_path = $self->persistent_path . "/" . $self->sid . "/reftree.json";
            if(-r $data_path && -r $tree_path) {
                #$self->_test->debug("Persistent file $data_path exists, reading from there\n");
                my $json = read_file($data_path);
                my $data = from_json($json);
                $self->_refdata($data);

                #$self->_test->debug("Persistent file $tree_path exists, reading from there\n");
                $json = read_file($tree_path);
                $data = from_json($json);
                $self->_reftree($data);

                $ref_done = 1;
            }
        }
    }
    unless($ref_done) {
        $self->_read_refdata();

        # if we read it from file, write it back to cache if enabled
        if($self->use_persistent) {
            my $path = $self->persistent_path . "/" . $self->sid;
            #$self->_test->debug("Checking for persistent path '$path'\n");
            if(-d $path) {
                #$self->_test->debug("Persistent path $path already exists, skip writing data\n");
            } else {
                #$self->_test->debug("Creating persistent path '$path'\n");
                make_path $path or die "Failed to create persistent path $path: $!\n";

                my $json = to_json($self->_refdata);
                my $fpath = "$path/refdata.json";
                open my $fh, ">", $fpath or die "Failed to open persistent file $fpath for writing: $!\n";
                print $fh $json;
                close $fh;

                $json = to_json($self->_reftree);
                $fpath = "$path/reftree.json";
                open $fh, ">", $fpath or die "Failed to open persistent file $fpath for writing: $!\n";
                print $fh $json;
                close $fh;
            }
        } else {
            #$self->_test->debug("Persistent feature disabled\n");
        }
    }

    $self->_read_depends();
}

sub _read_refdata {
    my ($self) = @_;

    my ($name,$path,$suffix) = fileparse(__FILE__);
    $path .= $self->ref_dir;

    my @files = File::Find::Rule->file()
        ->name('*.json')
        ->in(($path));

	my @json = ();
    foreach my $file(@files) {
        my $json = read_file($file)
            or die "Failed to open reference file '$file': $!\n";

        my $data= from_json($json);
        if(ref $data eq "ARRAY") {
            push @json, @{ $data };
        } elsif(ref $data eq "HASH") {
            push @json, $data;
        } else {
            die "Reference json file '$file' must contain array or object\n";
        }
    }

    $self->_refdata(\@json);

    foreach my $ref(@{ $self->_refdata }) {
        $self->_resolve_deps($ref->{name}, $ref);
    }

    #$self->_test->debug Dumper $self->_reftree;


}

sub _read_depends {
    my ($self) = @_;
    foreach my $d(@{ $self->depends }) {
        my $resource_found = 0;
        foreach my $k(keys %{ $self->_reftree }) {
            my $ref = $self->_reftree->{$k};
            #$self->_test->debug("++++ checking dependency '$$d{resource}' against reference '$$ref{name}' of type '$$ref{type}'\n");
            if($ref->{type} eq $d->{resource}) {
                #$self->_test->debug("+++ found a reference data entry of resource $$d{resource}\n");
                if(defined $d->{hints}) {
                    my $hint_found = 0;
                    foreach my $hint(@{ $d->{hints} }) {
               
                        #$self->_test->debug("+++ checking hint field $$hint{field} with expected value $$hint{value} against ".$ref->{data}->{$hint->{field}}."\n");
                        if(defined $hint->{name} && $hint->{name} eq $ref->{name}) {
                            $hint_found = 1;
                            $self->_dependstree->{$d->{name}} = $ref->{data};
                            last;
                        } elsif(defined $hint->{field} && exists $ref->{data}->{$hint->{field}} &&
                           "".$hint->{value} eq "".$ref->{data}->{$hint->{field}}) {

                            #$self->_test->debug("found reference data using hints:\n");
                            #$self->_test->debug Dumper $ref->{data};
                            $hint_found = 1;
                            $self->_dependstree->{$d->{name}} = $ref->{data};
                            last;
                        }
                    }
                    if($hint_found) {
                        $resource_found = 1;
                        last;
                    }
                } else {
                    #$self->_test->debug("found reference data:\n");
                    #$self->_test->debug Dumper $ref->{data};
                    $resource_found = 1;
                    $self->_dependstree->{$d->{name}} = $ref->{data};
                    last;
                }
            }
        }
        unless($resource_found) {
            die "No reference data for '$$d{resource}' found with given hints\n";
        }
    }
}

sub _replace_vars {
    my ($self, $var, $refname) = @_;

    if(ref $$var eq "HASH") {
        foreach my $k(keys %{ $$var }) {
            $self->_replace_vars(\$$var->{$k}, $refname);
        }
    } elsif(ref $$var eq "ARRAY") {
        foreach my $k(@{ $$var }) {
            $self->_replace_vars(\$k, $refname);
        }
    } elsif(ref $$var ne "") {
        return;
    } else {
        my @vars = $$var =~ /(\$\{.+?\})/g;
        $self->_test->debug("++++++ found vars in $refname:\n");
        $self->_test->debug(Dumper \@vars);
        foreach my $tvar(@vars) {
            my $val;
            my $revar = $tvar;
            $revar =~ s/([\$\{\}])/\\$1/g;
            $self->_test->debug("++++ replaced varname '$tvar' by revar '$revar'\n");
            if($tvar eq '${sid}') {
                $val = $self->sid;
                $self->_test->debug("++++ replace $tvar by sid $val\n");
            } else {
                my $len = length($tvar) - 3;
                my $varname = substr($tvar, 2, $len);
                $self->_test->debug("++++ extracted varname '$varname'\n");
                unless(exists $self->_reftree->{$varname}) {
                    die "Internal error, unresolved dependency '$varname'\n";
                }
                $val = $self->_reftree->{$varname}->{data}->{id};
            }
            $self->_test->debug("about to replace, before='$$var'\n");
            $$var =~ s/$revar/$val/g;
            $self->_test->debug("done replace, after='$$var'\n");
        }
    }
}

sub _resolve_deps {
    my ($self, $refname, $ref) = @_;

    #$self->_test->debug("---- entering _resolve_deps with refname='$refname' and ref=\n");
    #$self->_test->debug Dumper $ref;

    if(defined $ref) {
        if(exists $ref->{depends}) {
            foreach my $dep(@{ $ref->{depends} }) { 
                #$self->_test->debug("found dependency '$dep' on ref '$refname'\n");
                my $d = $self->_resolve_deps($dep);
                unless($d) {
                    die "Unresolved dependency '$dep' on '$refname'\n";
                }
                $self->_resolve_deps($dep, $d);
            }
            $self->_replace_vars(\$ref->{data}, $refname);

            unless($ref->{data}->{id}) {
                #$self->_test->debug("++++ '$refname' has no id yet, create via API, uri is 'api/$$ref{type}\n");
                #$self->_test->debug Dumper $ref->{data};
                my $url = 'api/'.$ref->{type};
                my $res = $self->client->_post('api/'.$ref->{type}, $ref->{data});
                unless($res->is_success) {
                    die "Failed to create $refname: ".$res->status_line."\n";
                }
                my $id = $res->header('Location');
                $id =~ s/^(.+\/)([^\/]+)$/$2/;
                $ref->{data}->{id} = $id; # TODO: refetch if no content?
                $url .= "/$id";
                $self->_reftree->{$refname} = $ref;
                push @{ $self->_refurls }, $url;
            }
            return $ref;
        }
    } else {
        if(exists $self->_reftree->{$refname}) {
            #$self->_test->debug("++++ found ref '$refname' in tree, just return it\n");
            return $self->_reftree->{$refname};
        } else {
            foreach my $ref(@{ $self->_refdata }) {
                if($ref->{name} eq $refname) {
                    #$self->_test->debug("++++ found ref '$refname' in JSON, return for creation\n");
                    return $ref;
                }
            }
        }
    }

}

sub data {
    my ($self, $name) = @_;
    if(exists $self->_dependstree->{$name}) {
        return $self->_dependstree->{$name};
    } else {
        die "Failed to find given dependency name '$name' in dependency tree, check name against 'depends' in constructor\n";
    }
}

sub DESTROY {
    my ($self) = @_;

	if($self->delete_persistent) {
		while((my $url = pop @{ $self->_refurls })) {
            #$self->_test->debug("+++++ deleting $url\n");
			my $res = $self->client->_delete($url);
            unless($res->is_success) {
                my $data = from_json($res->decoded_content);
                if($res->code == 404) {
			        my $res = $self->client->_patch($url, [{
                        op => 'replace',
                        path => '/status',
                        value => 'terminated'
                    }]);
                    unless($res->is_success) {
                        $self->_test->info("Failed to both auto-delete or auto-terminate '$url': $$data{message}\n");
                    } else {
                        #$self->_test->debug("+++++ $url successfully terminated\n");
                    }
                }
            } else {
                #$self->_test->debug("+++++ $url successfully deleted\n");
            }
		}
	}
}

1;
