package NGCP::Test;
use strict;
use warnings;

use Moose;
use TryCatch;
use NGCP::Test::Client;
use NGCP::Test::ReferenceData;
use NGCP::Test::Resource;
use Test::More;

has 'test_count' => (
    isa => 'Int',
    is => 'rw',
    default => 0,
);

has 'log_debug' => (
    isa => 'Bool',
    is => 'rw',
    default => 0,
);

sub client {
    my ($self, %args) = @_;

    $args{_test} = $self;
    return NGCP::Test::Client->new(%args);
}

sub reference_data {
    my ($self, %args) = @_;
    $args{_test} = $self;
    my $ref;
    my $err;
    try {
        $ref = NGCP::Test::ReferenceData->new(%args);
    } catch($e) {
        $err = $e;
    }
    ok($ref, "building reference data");
    $self->inc_test_count;
    $self->fatal($err) if $err;
    return $ref;
}

sub resource {
    my ($self, %args) = @_;
    $args{_test} = $self;
    return NGCP::Test::Resource->new(%args);
}

sub generate_sid {
    my ($self) = @_;
    my $sid = $ENV{NGCP_SESSION_ID} // "".int(rand(1000)).time;
}

sub done {
    my ($self) = @_;
    done_testing($self->test_count);
}

sub inc_test_count {
    my ($self) = @_;
    $self->test_count($self->test_count+1);
}

sub debug {
    my ($self, $msg) = @_;
    if($self->log_debug) {
        print $msg;
    }
}

sub info {
    my ($self, $msg) = @_;
    print $msg;
}

sub fatal {
    my ($self, $err) = @_;
    $self->done;
    die $err;
}

1;
