package NGCP::Test::Resource;
use strict;
use warnings;

use Moose;
use Test::More;
use Test::Deep qw/cmp_bag/;
use Clone qw/clone/;
use Data::Dumper;
use JSON qw/from_json to_json/;
use NGCP::Test::Patch;

has '_test' => (
    isa => 'Object',
    is => 'ro',
);

has 'client' => (
    isa => 'Object',
    is => 'rw',
);

has 'resource' => (
    isa => 'Str',
    is => 'ro',
);

has 'data' => (
    isa => 'Maybe[HashRef]',
    is => 'ro',
);

has 'allowed' => (
    isa => 'HashRef',
    is => 'ro',
    default => sub { { collection => [], item => [] } },
);

has 'autodelete_created_items' => (
    isa => 'Bool',
    is => 'rw',
    default => 1,
);

has 'print_summary_on_finish' => (
    isa => 'Bool',
    is => 'rw',
    default => 0,
);

has 'test_count' => (
    isa => 'Int',
    is => 'rw',
    default => 0,
);

has 'created_items' => (
    isa => 'ArrayRef',
    is => 'rw',
    default => sub {[]}
);

has 'requests' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub {[]},
);

sub BUILD {
    my $self = shift;
    unless($self->client) {
        die "Missing parameter 'client' when creating " . __PACKAGE__ . "\n";
    }
    unless($self->resource) {
        die "Missing parameter 'resource' when creating " . __PACKAGE__ . "\n";
    }
}

sub _process_input {
    my ($self, $args) = @_;

    my @data = ();
    my @qparams= ();
    my @expected = ();

    if(exists $args->{data_replace}) {
        my $ref = ref $args->{data_replace};
        if($ref eq 'HASH') {
            push @data, ($args->{data_replace});
        } elsif($ref eq 'ARRAY') {
            @data = @{ $args->{data_replace} };
        } else {
            die "Invalid 'data_replace' type, must be hashref or arrayref\n";
        }
    } else {
        @data = ($self->data);
    }
    if(exists $args->{expected_result}) {
        my $ref = ref $args->{expected_result};
        if($ref eq 'HASH') {
            @expected = map { $args->{expected_result} } (1 .. @data);
        } elsif($ref eq 'ARRAY') {
            @expected = @{ $args->{expected_result} };
            unless($#expected == $#data) {
                die "Number of elements in 'data_replace' doesn't match number of elements in 'expected_result'\n";
            }
        } else {
            die "Invalid 'data_replace' type, must be hashref or arrayref\n";
        }
    } else {
        die "Missing argument 'expected_result'\n";
    }
    if(exists $args->{query_params}) {
        my $ref = ref $args->{query_params};
        if($ref eq 'HASH') {
            push @qparams, ($args->{query_params});
        } elsif($ref eq 'ARRAY') {
            @qparams = @{ $args->{query_params} };
        } else {
            die "Invalid 'query_params' type, must be hashref or arrayref\n";
        }
    }

    return { data => \@data, expected => \@expected, qparams => \@qparams };
}

sub _get_replaced_data {
    my ($self, $data, $repl) = @_;

    my $allrepl = [];

    if(ref $repl eq "HASH") {
        push @{ $allrepl }, $repl;
    } elsif(ref $repl eq "ARRAY") {
        $allrepl = $repl;
    } else {
        die "All data_replace elements must be hashref or arrayref\n";
    }
    my $d = clone($data);
    foreach my $repl(@{ $allrepl }) {
        my $key = $repl->{field};
        my $val = $repl->{value};
        if(defined $key) {
            my @parts = split(/\./, $key);
            my $tmp = \$d;
            for(my $i = 0; $i < @parts; ++$i) {
                if($repl->{delete} && $i == @parts - 1) {
                    last;
                }
                $tmp = \$$$tmp{$parts[$i]};
            }
            if($repl->{delete}) {
                delete $$tmp->{$parts[$#parts]};
            } else {
                $$tmp = $val;
            }
        }
    }
    return $d;
}

sub _apply_patch {
    my ($self, $data, $json_patch) = @_;
   
    my $p = NGCP::Test::Patch->new;
    my $res = $p->apply_patch($data, $json_patch);
    return $res;

}

sub _get_patch_data {
    my ($self, $data, $repl) = @_;

    # TODO: support dot-style notation for nested fields

    my $key = $repl->{field};
    my $path = "/$key";
    $path =~ s/\./\//g;
    my $val = $repl->{value};
    my $op = $repl->{op};
    my $d = {
        op => $op,
        path => $path,
    };
    if($op eq "remove") {
        # no value to be set
    } elsif($op eq "copy" || $op eq "move") {
        # value is the "from" path
        my $from = "/$val";
        $from =~ s/\./\//g;
        $d->{from} = $from;
    } else {
        $d->{value} = $val;
    }
    $d = [$d];
    return $d;
}

sub _test_fields {
    my ($self, $skip, $expected, $ref, $item, $name) = @_;
    #print "++++ testing fields for $name\n";
    #print Dumper $ref;
    #print Dumper $item;

    $ref //= {};

    $skip //= [];
    my %skip = ();
    foreach my $s(@{ $skip }) {
        my @f = split /\./, $s;
        my $elem = \%skip;
        foreach my $p(@f) {
            $elem->{$p} = {};
            $elem = $elem->{$p};
        }
    }

    my %expect = map { $_ => 0 } @{ $expected // [] };
    foreach my $field(keys %{ $ref }) {
        next if($field eq "_links");

        if(defined $expected && exists $expect{$field}) {
            ok(exists $item->{$field}, "$name - expected field $field seen");
            $self->_inc_test_count;
            $expect{$field} = 1;
        }

        next if(exists $skip{$field} && !keys %{ $skip{$field} });

        if(defined $expected && !exists($expect{$field})) {
            next;
        }
        if(ref $ref->{$field} eq "ARRAY") {
            if(exists $skip{$field} && keys %{ $skip{$field} } && @{ $ref->{$field} } && ref $ref->{$field}->[0] eq "HASH") {
                for(my $i = 0; $i < @{ $ref->{$field} }; ++$i) {
                    my $refelem = $ref->{$field}->[$i];
                    my $elem = $item->{$field}->[$i];
                    my $k = (keys %{ $skip{$field} })[0]; 
                    my $refold = delete $refelem->{$k};
                    my $old = delete $elem->{$k};
                    is_deeply($elem, $refelem, $name . " - content of $field");
                    $self->_inc_test_count;
                    $refelem->{$k} = $refold;
                    $elem->{$k} = $old;
                }
                is(@{ $ref->{$field} }, @{ $item->{$field} }, "$name - element count of $field");
                $self->_inc_test_count;
            } else {
                cmp_bag($item->{$field}, $ref->{$field}, $name . " - content of $field");
                $self->_inc_test_count;
            }
        } elsif(ref $ref->{$field} eq "HASH") {
            if(exists $skip{$field} && keys %{ $skip{$field} }) {
                my $k = (keys %{ $skip{$field} })[0]; 
                my $refold = delete $ref->{$field}->{$k};
                my $old = delete $item->{$field}->{$k};
                is_deeply($item->{$field}, $ref->{$field}, $name . " - content of $field");
                $self->_inc_test_count;
                $ref->{$field}->{$k} = $refold;
                $item->{$field}->{$k} = $old;
            } else {
                is_deeply($item->{$field}, $ref->{$field}, $name . " - content of $field");
                $self->_inc_test_count;
            }
        } elsif(ref $ref->{$field} ne "") {
            is_deeply($item->{$field}, $ref->{$field}, $name . " - content of $field");
            $self->_inc_test_count;
        } else {
            is($item->{$field}, $ref->{$field}, $name . " - content of $field");
            $self->_inc_test_count;
        }
    }
    if(defined $expected) {
        foreach my $field(keys %{ $item }) {
            next if($field eq "_links");
            ok(exists $expect{$field}, "$name - field $field expected");
            $self->_inc_test_count;
            delete $expect{$field};
        }
        foreach my $field(keys %expect) {
            delete $expect{$field} if($expect{$field} == 1);
        }
    }

    if(!ok(keys %expect == 0, "$name - all expected fields seen")) {
        diag("the following expected fields were not seen: " . join(', ', keys %expect));
        diag("existing fields were: " . join(', ', keys %{ $item }));
    }
    $self->_inc_test_count;
}

sub test_allowed_methods {
    my ($self, $item) = @_;

    # while at it, test without item as well
    if(defined $item) {
        $self->test_allowed_methods();
    }

    my $res;
    my $expected;
    my $name = $self->resource . ' - allowed methods';
    if(defined $item) {
        $res = $self->client->_options('api/'.$self->resource.'/'.$item->{id});
        $name .= " - item";
        $expected = $self->allowed->{item};
    } else {
        $res = $self->client->_options('api/'.$self->resource);
        $name .= " - collection";
        $expected = $self->allowed->{collection};
    }

    is($res->code, 200, "$name - options request");
    $self->_inc_test_count;

    return unless($res->is_success);
    my $data = from_json($res->decoded_content);
    my $methods = $data->{methods};

    my @hopts = split /\s*,\s*/, $res->header('Allow');

    is(@hopts, @{ $expected }, "$name - correct amount of allowed methods in header");
    $self->_inc_test_count;
    is(@{ $methods }, @{ $expected }, "$name - correct amount of allowed methods in body");
    $self->_inc_test_count;

    while((my $opt = shift @{ $expected })) {
        ok(grep(/^$opt$/, @hopts), "$name - '$opt' in Allow header");
        $self->_inc_test_count;
        ok(grep(/^$opt$/, @{ $methods }), "$name - '$opt' in body");
        $self->_inc_test_count;
    }
    is(@{ $expected }, 0, "$name - no leftover in allowed methods");
    $self->_inc_test_count;
}

sub test_empty_bodies {
    my ($self, $item) = @_;

    # while at it, test without item as well
    if(defined $item) {
        $self->test_empty_bodies();
    }

    my $res;
    my $name = $self->resource . ' - missing body';
    if(defined $item) {
        $name .= " - put";
        $res = $self->client->_put('api/'.$self->resource.'/'.$item->{id}, undef);
        is($res->code, 400, $name); 
        $self->_inc_test_count;

        $name .= " - patch";
        $res = $self->client->_patch('api/'.$self->resource.'/'.$item->{id}, undef);
        is($res->code, 400, $name); 
        $self->_inc_test_count;
    } else {
        $name .= " - post";
        $res = $self->client->_post('api/'.$self->resource, undef);
        is($res->code, 400, $name); 
        $self->_inc_test_count;
    }
}

sub test_invalid_headers {
    my ($self, $item) = @_;

    # while at it, test without item as well
    if(defined $item) {
        $self->test_invalid_headers();
    }

    my $res;
    my $data;
    my $testname = $self->resource . ' - invalid headers';
    my $name;
    if(defined $item) {
        $name = "$testname - put without content-type";
        $res = $self->client->_put('api/'.$self->resource.'/'.$item->{id}, $item, '', undef);
        is($res->code, 415, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Unsupported Media Type/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        like($data->{message}, qr/'undefined', accepting application\/json only/, "$name - error");
        $self->_inc_test_count;

        $name = "$testname - put with invalid content-type";
        $res = $self->client->_put('api/'.$self->resource.'/'.$item->{id}, $item, 'something/invalid', undef);
        is($res->code, 415, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Unsupported Media Type/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        like($data->{message}, qr/'something\/invalid', accepting application\/json only/, "$name - error");
        $self->_inc_test_count;

        $name = "$testname - patch without content-type";
        $res = $self->client->_patch('api/'.$self->resource.'/'.$item->{id}, $item, '', undef);
        is($res->code, 415, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Unsupported Media Type/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        like($data->{message}, qr/'undefined', accepting application\/json-patch\+json only/, "$name - error");
        $self->_inc_test_count;

        $name = "$testname - patch with invalid content-type";
        $res = $self->client->_patch('api/'.$self->resource.'/'.$item->{id}, $item, 'application/json', undef);
        is($res->code, 415, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Unsupported Media Type/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        like($data->{message}, qr/'application\/json', accepting application\/json-patch\+json only/, "$name - error");
        $self->_inc_test_count;

        $name = "$testname - put without prefer";
        $res = $self->client->_put('api/'.$self->resource.'/'.$item->{id}, $item, undef, '');
        is($res->code, 204, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/No Content/, "$name - status"); 
        $self->_inc_test_count;
        is($res->decoded_content, '', "$name - no content");
        $self->_inc_test_count;

        $name = "$testname - put with invalid prefer";
        $res = $self->client->_put('api/'.$self->resource.'/'.$item->{id}, $item, undef, 'something=invalid');
        is($res->code, 400, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Bad Request/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        like($data->{message}, qr/Header 'Prefer' must be either 'return=minimal' or 'return=representation'/, "$name - error");
        $self->_inc_test_count;

        $name = "$testname - patch without prefer";
        $res = $self->client->_patch('api/'.$self->resource.'/'.$item->{id}, [], undef, '');
        is($res->code, 204, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/No Content/, "$name - status"); 
        $self->_inc_test_count;
        is($res->decoded_content, '', "$name - no content");
        $self->_inc_test_count;

        $name = "$testname - patch with invalid prefer";
        $res = $self->client->_patch('api/'.$self->resource.'/'.$item->{id}, $item, undef, 'something=invalid');
        is($res->code, 400, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Bad Request/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        like($data->{message}, qr/Header 'Prefer' must be either 'return=minimal' or 'return=representation'/, "$name - error");
        $self->_inc_test_count;

    } else {
        $item = { test => 'test' };
        $name = "$testname - post without content-type";
        $res = $self->client->_post('api/'.$self->resource, $item, '', undef);
        is($res->code, 415, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Unsupported Media Type/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        like($data->{message}, qr/Unsupported media type 'undefined', accepting application\/json only/, "$name - error");
        $self->_inc_test_count;

        $name = "$testname - post with invalid content-type";
        $res = $self->client->_post('api/'.$self->resource, $item, 'something/invalid', undef);
        is($res->code, 415, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Unsupported Media Type/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        like($data->{message}, qr/'something\/invalid', accepting application\/json only/, "$name - error");
        $self->_inc_test_count;

        $name = "$testname - post without prefer";
        $res = $self->client->_post('api/'.$self->resource, {}, undef, '');
        is($res->code, 422, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Unprocessable Entity/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        # we assume here that at least ANY field must be existent in a post
        like($data->{message}, qr/Validation failed/, "$name - error");
        $self->_inc_test_count;

        $name = "$testname - post with invalid prefer";
        $res = $self->client->_post('api/'.$self->resource, $item, undef, 'something=invalid');
        is($res->code, 400, "$name - code"); 
        $self->_inc_test_count;
        like($res->message, qr/Bad Request/, "$name - status"); 
        $self->_inc_test_count;
        $data = from_json($res->decoded_content);
        like($data->{message}, qr/Header 'Prefer' must be either 'return=minimal' or 'return=representation'/, "$name - error");
        $self->_inc_test_count;
    }
}

sub _test_link {
    my ($self, $href, $name) = @_;
    my $res = $self->client->_get($href);
    $self->_push_request($name, $res);
    return $res->is_success;
}

sub _test_item {
    my ($self, $item, $args, $name, $ref) = @_;

    ok(!exists $item->{_embedded}, "$name - absence of _embedded in item");
    $self->_inc_test_count;
    ok(!exists $item->{total_count}, "$name - absence of total_count in item");
    $self->_inc_test_count;
    $self->_test_fields($args->{skip_test_fields}, $args->{expected_fields}, $ref, $item, $name);
    my %links = map { $_ => 0 } @{ $args->{expected_links} };
    foreach my $link(keys %{ $item->{_links} }) {
        next if(grep(/^$link$/, qw/self curies profile collection/));
        ok(exists $links{$link}, "$name - existence of link $link in reference");
        $self->_inc_test_count;
        delete $links{$link};
        ok($self->_test_link($item->{_links}->{$link}->{href}, $name), "$name - follow link to $link");
        $self->_inc_test_count;
    }
    if(!ok(keys %links == 0, "$name - missing links")) {
        diag("missing links: " . join(", ", keys %links));
    }
    $self->_inc_test_count;
}

sub test_get {
    my ($self, %args) = @_;
    my $testname = $self->resource . ' - ' . ($args{name} // 'test_get');
    my $ref = $args{item};
    my $input = $self->_process_input(\%args);
    unless(@{ $input->{qparams} }) {
        $input->{qparams} = [{}];
    }

    my @qparams = @{ $input->{qparams} };
    my @expected = @{ $input->{expected} };
    my @items = ();

    if($ref && @qparams != 1) {
        die "When providing a reference 'item', query_params must contain one row only\n";
    }

    for(my $i = 0; $i < @qparams; ++$i) {
        my $e = $expected[$i];
        my $q = $qparams[$i];
        my $name = "$testname $i";

        my $uri = 'api/'.$self->resource . ($ref ? "/$$ref{id}" : "");
        my @tmpq = ();
        foreach my $k(keys %{ $q }) {
            push @tmpq, "$k=$$q{$k}"; 
        }
        if(@tmpq) {
            $uri .= '?' . join('&', @tmpq);
        }

        my $res = $self->client->_get($uri);
        is($res->code, $e->{code}, $name . " - code");
        $self->_inc_test_count;
        if(exists $e->{reason_re}) {
            like($res->message, qr/$e->{reason_re}/, $name . " - message");
            $self->_inc_test_count;
        } elsif(exists $e->{error_re}) {
            ok(!$res->is_success, $name . " - is an error");
            $self->_inc_test_count;
            my $item = from_json($res->decoded_content);
            like($item->{message}, qr/$e->{error_re}/, $name . " - error message");
            $self->_inc_test_count;
        }

        if($res->code =~ /^2\d\d$/) {
            my $item = from_json($res->decoded_content);
            push @items, $item;
            if($ref) {
                $self->_test_item($item, \%args, $name, $ref);
            } else {
                ok(exists $item->{total_count}, "$name - presence of total_count in collection");
                $self->_inc_test_count;
                if($item->{total_count}) {
                    ok(exists $item->{_embedded}, "$name - presence of _embedded in collection on data");
                    $self->_inc_test_count;
                }
                if(exists $args{expected_count}) {
                    is($item->{total_count}, $args{expected_count}, "$name - total_count value");
                    $self->_inc_test_count;
                }
                foreach my $subitem(@{ $item->{_embedded}->{"ngcp:".$self->resource} }) {
                    $self->_test_item($subitem, \%args, $name, undef);
                }
            }

        }
    }
    return \@items;
}


sub test_post {
    my ($self, %args) = @_;
    my $testname = $self->resource . ' - ' . ($args{name} // 'test_post');

    my $input = $self->_process_input(\%args);

    my @data = @{ $input->{data} };
    my @expected = @{ $input->{expected} };

    for(my $i = 0; $i < @data; ++$i) {

        my $d = $self->_get_replaced_data($self->data, $data[$i]);
        my $e = $expected[$i];
        my $name = "$testname $i";

        # fire request and test result
        my $res = $self->client->_post('api/'.$self->resource, $d);
        $self->_push_request($name, $res);
        is($res->code, $e->{code}, $name . " - code");
        $self->_inc_test_count;
        if(exists $e->{reason_re}) {
            like($res->message, qr/$e->{reason_re}/, $name . " - message");
            $self->_inc_test_count;
        } elsif(exists $e->{error_re}) {
            ok(!$res->is_success, $name . " - is an error");
            $self->_inc_test_count;
            my $item = from_json($res->decoded_content);
            like($item->{message}, qr/$e->{error_re}/, $name . " - error message");
            $self->_inc_test_count;
        }
        # copy created item into cache
        if($res->code =~ /^2\d\d$/) {
            my $item;
            if($res->decoded_content) {
                # TODO: do we need to extract from JSON::HAL?
                $item = from_json($res->decoded_content);
            } else {
                my $id = $res->header('Location');
                $id =~ s/^.+\/([^\/]+)$/$1/;
                $res = $self->client->_get('api/'.$self->resource.'/'.$id);
                $self->_push_request($name, $res);
                unless($res->is_success) {
                    die "Failed to re-fetch created resource " . $self->resource . " with id $id\n";
                }
                # TODO: do we need to extract from JSON::HAL?
                $item = from_json($res->decoded_content);
            }
            $self->push_created_item($item);
            $self->_test_fields($args{skip_test_fields}, $args{expected_fields}, $d, $item, $name);
        }
    }
}

sub test_put {
    my ($self, %args) = @_;
    my $testname = $self->resource . ' - ' . ($args{name} // 'test_put');
    my $item = $args{item};

    my $input = $self->_process_input(\%args);

    my @data = @{ $input->{data} };
    my @expected = @{ $input->{expected} };

    my @items = ();

    for(my $i = 0; $i < @data; ++$i) {

        my $d = $self->_get_replaced_data($item, $data[$i]);
        my $e = $expected[$i];
        my $name = "$testname $i";

        # fire request and test result
        my $res = $self->client->_put('api/'.$self->resource.'/'.$d->{id}, $d);
        $self->_push_request($name, $res);
        is($res->code, $e->{code}, $name . " - code");
        $self->_inc_test_count;
        if(exists $e->{reason_re}) {
            like($res->message, qr/$e->{reason_re}/, $name . " - message");
            $self->_inc_test_count;
        } elsif(exists $e->{error_re}) {
            ok(!$res->is_success, $name . " - is an error");
            $self->_inc_test_count;
            my $item = from_json($res->decoded_content);
            like($item->{message}, qr/$e->{error_re}/, $name . " - error message");
            $self->_inc_test_count;
        }
        if($res->code =~ /^2\d\d$/ && $res->decoded_content) {
            # TODO: do we need to extract from JSON::HAL?
            my $resitem = from_json($res->decoded_content);
            push @items, $resitem;
            $self->_test_fields($args{skip_test_fields}, $args{expected_fields}, $d, $resitem, $name);
        } else {
            push @items, $item;
        }
    }
    return \@items;
}


sub test_patch {
    my ($self, %args) = @_;
    my $testname = $self->resource . ' - ' . ($args{name} // 'test_patch');
    my $item = $args{item};

    my $input = $self->_process_input(\%args);

    my @data = @{ $input->{data} };
    my @expected = @{ $input->{expected} };

    my @items = ();

    for(my $i = 0; $i < @data; ++$i) {

        my $d = $self->_get_patch_data($item, $data[$i]);
        my $refd = $self->_apply_patch($item, to_json($d));
        my $e = $expected[$i];
        my $name = "$testname $i";

        # fire request and test result
        my $res = $self->client->_patch('api/'.$self->resource.'/'.$item->{id}, $d);
        $self->_push_request($name, $res);
        is($res->code, $e->{code}, $name . " - code");
        $self->_inc_test_count;
        if(exists $e->{reason_re}) {
            like($res->message, qr/$e->{reason_re}/, $name . " - message");
            $self->_inc_test_count;
        } elsif(exists $e->{error_re}) {
            ok(!$res->is_success, $name . " - is an error");
            $self->_inc_test_count;
            my $item = from_json($res->decoded_content);
            like($item->{message}, qr/$e->{error_re}/, $name . " - error message");
            $self->_inc_test_count;
        }
        if($res->code =~ /^2\d\d$/ && $res->decoded_content) {
            # TODO: do we need to extract from JSON::HAL?
            my $resitem = from_json($res->decoded_content);
            push @items, $resitem;
            $self->_test_fields($args{skip_test_fields}, $args{expected_fields}, $refd, $resitem, $name);
        } else {
            push @items, $item;
        }
    }
    return \@items;
}

sub test_delete {
    my ($self, %args) = @_;
    my $testname = $self->resource . ' - ' . ($args{name} // 'test_delete');
    my $item = $args{item};

    my $input = $self->_process_input(\%args);

    my @data = @{ $input->{data} };
    my @expected = @{ $input->{expected} };

    my @items = ();

    for(my $i = 0; $i < @data; ++$i) {

        my $d = $self->_get_replaced_data($item, $data[$i]);
        my $e = $expected[$i];
        my $name = "$testname $i";

        # fire request and test result
        my $res = $self->client->_delete('api/'.$self->resource.'/'.$d->{id});
        $self->_push_request($name, $res);
        is($res->code, $e->{code}, $name . " - code");
        $self->_inc_test_count;
        if(exists $e->{reason_re}) {
            like($res->message, qr/$e->{reason_re}/, $name . " - message");
            $self->_inc_test_count;
        } elsif(exists $e->{error_re}) {
            ok(!$res->is_success, $name . " - is an error");
            $self->_inc_test_count;
            my $item = from_json($res->decoded_content);
            like($item->{message}, qr/$e->{error_re}/, $name . " - error message");
            $self->_inc_test_count;
        }
    }
}

=pod
# TODO: not needed?
sub _update_created_item {
    my ($self, $item) = @_;
    for(my $i = 0; $i < $self->count_created_items(); ++$i) {
        if($self->created_items->[$i]->{id} eq $item->{id}) {
            print "found old item in cache\n";
            @{$self->created_items}[$i] = $item;
        }
    }
}
=cut

sub _inc_test_count {
    my ($self) = @_;
    $self->_test->inc_test_count();
}

sub push_created_item {
    my ($self, $item) = @_;
    push @{ $self->created_items }, $item;
}

sub pop_created_item {
    my ($self) = @_;
    my $item = pop @{ $self->created_items };
    return $item;
}

sub shift_created_item {
    my ($self) = @_;
    my $item = shift @{ $self->created_items };
    return $item;
}

sub count_created_items {
    my ($self) = @_;
    return 0 + @{ $self->created_items };
}

sub print_summary {
    my ($self) = @_;

    diag("Performed Requests:");
    my $i = 0;
    foreach my $r(@{ $self->requests }) {
        $i++;
        diag("$$r{testname}:");
        diag("$$r{method} $$r{uri}");
        diag("$$r{code} $$r{message}");
        diag("rtt: $$r{rtt}");
        diag("");
    }
    diag("Total: $i");
}

sub _push_request {
    my ($self, $name, $res) = @_;
    push @{ $self->requests }, {
        testname => $name,
        method => $res->request->method,
        uri => $res->request->uri,
        code => $res->code,
        message => $res->message,
        rtt => $self->client->last_rtt,
    };
}


sub DEMOLISH {
    my ($self) = @_;
    my @failed = ();
    my @threads = ();
    if($self->autodelete_created_items) {
        while((my $item = $self->pop_created_item())) {
            my $id = $item->{id};
            my $url = 'api/'.$self->resource.'/'.$id;
            my $res = $self->client->_delete($url);
            unless($res->is_success) {
                my $data = from_json($res->decoded_content);
                if($res->code == 404) {
			        $res = $self->client->_patch($url, [{
                        op => 'replace',
                        path => '/status',
                        value => 'terminated'
                    }]);
                    unless($res->is_success) {
                        diag("Failed to both auto-delete or auto-terminate '$url': $$data{message}");
                        push @failed, $id;
                    } else {
                        #print "+++++ $url successfully terminated\n";
                    }
                }
            } else {
                #print "+++++ $url successfully deleted\n";
            }

            $self->_push_request('autodelete', $res);
        }
        if(@failed) {
            diag("failed to auto-delete the following " . 
                $self->resource . ": " .  (join ', ', @failed));
        }
    }
    if($self->print_summary_on_finish) {
        $self->print_summary();
    }
}

1;
