#!/usr/bin/perl -w

use v5.14;
use JSON qw();
use LWP::UserAgent;
use IO::Socket::SSL;
use IPC::Shareable;
use Time::HiRes qw(usleep);

my $user = 'administrator';
my $pass = 'administrator';
my $host = 'demo-dev.sipwise.com';
my $port = 1443;

my $domain = 'bench.demo-dev.sipwise.com';
my $reseller_id = 1;
my $billprof_id = 1;

my $customers = 50000;
my $subs_per_customer = 1;

my $customer_type = 'sipaccount';
my $uri_base = 'bench2user';
my $password = 'testuser';
my $number_cc = '43';
my $number_ac = '717';

my $procs = 8;

sub work;

# our shared counters
my $count_customers;
my $handle_customers = tie $count_customers, 'IPC::Shareable', undef, { destroy => 1 };
$count_customers = 0;

my $count_kids_done;
my $handle_kids_done = tie $count_kids_done, 'IPC::Shareable', undef, { destroy => 1 };
$count_kids_done = 0;

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
my $ua = LWP::UserAgent->new();
$ua->ssl_opts(
	verify_hostname => 0,
	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
);
$ua->credentials("$host:$port", 'api_admin_http', $user, $pass);

my ($req, $res);
my $domain_id;

$req = HTTP::Request->new('GET', "$urlbase/api/domains/?domain=$domain");
$res = $ua->request($req);
if($res->is_success) {
	my $collection = JSON::from_json($res->decoded_content);
	$domain_id = $collection->{_embedded}->{'ngcp:domains'}->{id};
	unless($domain_id) {
		die "Failed to fetch id for domain '$domain', no such domain?";
	}
} else {
	die "Failed to fetch fetch domain id";
}
say "Domain '$domain' has id $domain_id";

my @kids = ();
my $chunk_start = 0;
my $proc_chunk_first = 0;
my $proc_chunk_last = 0;
say "chunk size is $chunk_size, last chunk size is $last_chunk_size";
for(my $i = 0; $i < $procs; ++$i) {
	my $child;
	if($i == $procs-1) {
		$proc_chunk_last = $proc_chunk_first + $last_chunk_size - 1;
	} else {
		$proc_chunk_last = $proc_chunk_first + $chunk_size - 1;
	}
	unless($child = fork()) {
		die "Failed to fork worker process: $!\n" unless defined $child;
		work();
		exit;
	}
	push @kids, $child;
	$proc_chunk_first = $proc_chunk_last + 1;
}

my $last_customers = 0;
while($count_kids_done < $procs) {
	my $customers_psec = $count_customers - $last_customers;
	say sprintf('%05.2f', ($count_customers / $customers * 100.0))."% at $customers_psec/sec";
	$last_customers = $count_customers;
	sleep 1;
}
say "Done creating $count_customers";

sub work {
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
			die "Failed to create customer contact";
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
			die "Failed to create customer";
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
				die "Failed to create subscriber";
			}
		}
	}
	$handle_kids_done->shlock();
	$count_kids_done++;
	$handle_kids_done->shunlock();
}


