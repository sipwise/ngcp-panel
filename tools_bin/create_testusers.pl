#!/usr/bin/perl

use strict;
use warnings;
use v5.14;
use JSON qw();
use LWP::UserAgent;
use IO::Socket::SSL;
use IPC::Shareable;
use Time::HiRes qw(usleep gettimeofday tv_interval);
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;

my $user = 'administrator';
my $pass = 'administrator';
my $host = 'localhost';
my $port = 1443;

my $domain = 'bench.demo-dev.sipwise.com';
my $reseller_id = 1;
my $billprof_id = 1;

my $customers = 50000;
my $subs_per_customer = 1;

my $customer_type = 'sipaccount';
my $uri_base = 'benchuser';
my $password = 'password';
my $number_cc = '43';
my $number_ac = '111';

my $procs = 8;

my $certpath;

my $help = undef;
my $man = undef;

GetOptions(
    "procs=i"               => \$procs,
    "cert=s"                => \$certpath,
    "api-user=s"            => \$user,
    "api-pass=s"            => \$pass,
    "api-host=s"            => \$host,
    "api-port=i"            => \$port,
    "reseller-id=i"         => \$reseller_id,
    "billprof-id=i"         => \$billprof_id,
    "domain=s"              => \$domain,
    "customers=i"           => \$customers,
    "subs-per-customer=i"   => \$subs_per_customer,
    "customer-type=s"       => \$customer_type,
    "uri-base=s"            => \$uri_base,
    "sip-password=s"        => \$password,
    "number-cc=i"           => \$number_cc,
    "number-ac=i"           => \$number_ac,
    "help|?"                => \$help,
    "man"                   => \$man,
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;

say "Running with the following config:";
say "   procs=$procs";
say "   cert=" . ($certpath // "<none>");
say "   api-user=$user";
say "   api-pass=$pass";
say "   api-host=$host";
say "   api-port=$port";
say "   reseller-id=$reseller_id";
say "   billprof-id=$billprof_id";
say "   domain=$domain";
say "   customers=$customers";
say "   subs-per-customer=$subs_per_customer";
say "   customer-type=$customer_type";
say "   uri-base=$uri_base";
say "   sip-password=$password";
say "   number-cc=$number_cc";
say "   number-ac=$number_ac";
print "Proceed <YES|no>: ";
my $confirm = <STDIN>;
chomp $confirm;
if($confirm eq "" || lc($confirm) eq "yes") {
    say "Proceeding as requested.";
} else {
    die "Aborting as requested.\n";
}

sub work;

# our shared counters
my $count_customers;
my $handle_customers = tie $count_customers, 'IPC::Shareable', undef, { destroy => 1 };
$count_customers = 0;

my $count_kids_done;
my $handle_kids_done = tie $count_kids_done, 'IPC::Shareable', undef, { destroy => 1 };
$count_kids_done = 0;

my $has_error;
my $handle_error = tie $has_error, 'IPC::Shareable', undef, { destroy => 1 };
$has_error = 0;

my $chunk_size = int($customers/$procs);
my $chunk_rest = $customers % $procs;
my $last_chunk_size;
if($chunk_rest > $procs) {
    $chunk_size += int($chunk_rest/$procs);
    $last_chunk_size = $chunk_size + ($chunk_rest % $procs);
} else {
    $last_chunk_size = $chunk_size + ($customers % $procs);
}

my $urlbase = "https://$host:$port";

sub create_ua {
    my $ua = LWP::UserAgent->new(keep_alive => 1);
    $ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
        $certpath ? (
            SSL_cert_file => $certpath,
            SSL_key_file  => $certpath,
        ) : (),
    );
    $ua->credentials("$host:$port", 'api_admin_http', $user, $pass);
    return $ua;
}

my ($req, $res);
my $domain_id;

my $ua = create_ua();
$req = HTTP::Request->new('GET', "$urlbase/api/domains/?domain=$domain");
$res = $ua->request($req);
if($res->is_success) {
    my $collection = JSON::from_json($res->decoded_content);
    if($collection->{total_count} == 0) {
        say "Domain '$domain' not found, creating...";
        $req = HTTP::Request->new('POST', "$urlbase/api/domains/");
        $req->content_type('application/json');
        $req->content(JSON::to_json({
            reseller_id => $reseller_id,
            domain => $domain,
        }));
        $res = $ua->request($req);
        if($res->is_success) {
            say "Domain '$domain' created, proceeding...";
            $domain_id = $res->header('Location');
            $domain_id =~ s/^.+\/(\d+)$/$1/;
        } else {
            die "Failed to create domain '$domain': " . $res->status_line . "\n";
        }
    } else {
        my $col = $collection->{_embedded}->{'ngcp:domains'};
        if(ref $col eq "HASH") {
            $domain_id = $col->{id};
        } elsif(ref $col eq "ARRAY") {
            $domain_id = $col->[0]->{id};
        } else {
            die "Invalid HAL response when fetching domain '$domain':\n" . (Dumper $col) . "\n";

        }
    }
} else {
    die "Failed to fetch fetch domain id: " . $res->status_line . "\n";
}
say "Domain '$domain' has id $domain_id";

my @kids = ();
my $chunk_start = 0;
my $proc_chunk_first = 0;
my $proc_chunk_last = 0;
say "chunk size is $chunk_size, last chunk size is $last_chunk_size";
my $t0 = [gettimeofday];
my $pid;
for(my $i = 0; $i < $procs; ++$i) {
    if($i == $procs-1) {
        $proc_chunk_last = $proc_chunk_first + $last_chunk_size - 1;
    } else {
        $proc_chunk_last = $proc_chunk_first + $chunk_size - 1;
    }
    unless($pid = fork()) {
        die "Failed to fork worker process: $!\n" unless defined $pid;
        work();
        exit;
    }
    push @kids, $pid;
    $proc_chunk_first = $proc_chunk_last + 1;
}

my $last_customers = 0;
while($count_kids_done < $procs && !$has_error) {
    my $customers_psec = $count_customers - $last_customers;
    say sprintf('%05.2f', ($count_customers / $customers * 100.0))."% at $customers_psec/sec";
    $last_customers = $count_customers;
    sleep 1;
}
if($has_error) {
    kill 'TERM', @kids;
}

say "Processing done, collecting final status...";
if($pid > 0) {
    my $last_kids = @kids;
    while((my $child_pid = wait()) > 0 && @kids) {
        @kids = grep { !/^$child_pid$/ } @kids;
        if(@kids == $last_kids) {
            sleep 1;
        }
        $last_kids = @kids;
    }
}
if($has_error) {
    say "Processing has failed with errors!";
} else {
    say "Done creating $count_customers customers";
    my $duration = tv_interval($t0);
    say "Overall duration was $duration with " .
        ($customers/$duration) . " customers per sec and " .
        ($duration/$customers) . " sec per customer";
}

sub mydie {
    my $msg = shift;
    $has_error = 1;
    die $msg;
}

sub work {
    $ua = create_ua();
    # TODO: make it in chunks, since other procs are doing the same!
    for(my $i = $proc_chunk_first; $i <= $proc_chunk_last; ++$i) {

        $handle_customers->shlock();
        $count_customers++;
        $handle_customers->shunlock();

        my ($contact_id, $customer_id, $subscriber_id);
        $req = HTTP::Request->new('POST', "$urlbase/api/customercontacts/");
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            reseller_id => $reseller_id,
            email => sprintf('customer%06d@sipwise.internal', $i),
        }));
        $res = $ua->request($req);
        if($res->is_success) {
            $contact_id = $res->header('Location');
            $contact_id =~ s/^.*\/(\d+)$/$1/;
        } else {
            mydie("Failed to create customer contact: " . $res->status_line . "\n");
        }

        $req = HTTP::Request->new('POST', "$urlbase/api/customers/");
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            billing_profile_id => $billprof_id,
            contact_id => $contact_id,
            external_id => $i,
            status => 'active',
            type => $customer_type,
        }));
        $res = $ua->request($req);
        if($res->is_success) {
            $customer_id = $res->header('Location');
            $customer_id =~ s/^.*\/(\d+)$/$1/;
        } else {
            mydie("Failed to create customer: " . $res->status_line . "\n");
        }

        for(my $j = 0; $j < $subs_per_customer; ++$j) {
            $req = HTTP::Request->new('POST', "$urlbase/api/subscribers/");
            $req->header('Content-Type' => 'application/json');
            $req->content(JSON::to_json({
                customer_id => $customer_id,
                domain_id => $domain_id,
                password => $password,
                primary_number => { cc => $number_cc, ac => $number_ac, sn => sprintf('%06d', $i).sprintf('%03d', $j) },
                status => 'active',
                username => $uri_base.sprintf('%06d', $i).sprintf('%03d', $j),
            }));
            $res = $ua->request($req);
            if($res->is_success) {
                $subscriber_id = $res->header('Location');
                $subscriber_id =~ s/^.*\/(\d+)$/$1/;
            } else {
                mydie("Failed to create subscriber: " . $res->status_line . "\n");
            }
        }
    }
    $handle_kids_done->shlock();
    $count_kids_done++;
    $handle_kids_done->shunlock();
}

__END__

=head1 NAME

create_testusers.pl

=head1 DESCRIPTION

Optimized batch-creation for test customers/subscribers

=head1 SYNOPSIS

create_testusers.pl [options]

Options:

    --procs=i
    --api-user=s
    --api-pass=s
    --api-host=s
    --api-port=i
    --reseller-id=i
    --billprof-id=i
    --domain=s
    --customers=i
    --subs-per-customer=i
    --customer-type=s
    --uri-base=s
    --sip-password=s
    --number-cc=i
    --number-ac=i

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
