package NGCP::Panel::Utils::Fax;

use English;
use File::Temp qw/tempfile/;
use File::Slurp;
use TryCatch;
use IPC::System::Simple qw/capture/;
use Data::Dumper;
use Net::Ping;

sub send_fax {
    my (%args) = @_;
    my $c = $args{c};

    #moved here due to CE, as it doesn't carry NGCP::fax
    eval { require NGCP::Fax; };
    if ($@) {
        if ($@ =~ m#Can't locate NGCP/Fax.pm#) {
            $c->log->debug("Fax features are not supported in the Community Edition");
            return;
        } else {
            die $@;
        }
    }
    my $subscriber = $args{subscriber};
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    my %sendfax_args = ();

    if (defined $c->config->{faxserver}{hosts}) {
        my @hosts = split(/,\s*/, $c->config->{faxserver}{hosts});
        my $port = $c->config->{faxserver}{port};
        my $ping = new Net::Ping('tcp', 1);
        $ping->port_number($port);
        do {
            my $host = $hosts[rand @hosts];
            if ($ping->ping($host)) {
                $sendfax_args{host} = $host;
                $sendfax_port{port} = $port;
            }
            @hosts = grep { $_ ne $host } @hosts;
        } while (!$sendfax_args{host} && @hosts);
        die "No alive proxy hosts to queue the send fax to" unless @hosts;
    }

    my $sender = 'webfax';
    my $number;
    if($subscriber->primary_number) {
        $number = $subscriber->primary_number->cc .
            ($subscriber->primary_number->ac // '').
            $subscriber->primary_number->sn;
    } else {
        $number = $sender;
    }
    $sendfax_args{caller} = $number;
    $sendfax_args{callee} = $args{destination};

    if($args{quality}) {#low|medium|extended
        $sendfax_args{quality} = $args{quality};
    }
    if($args{pageheader}) {
        $sendfax_args{header} = $args{pageheader};
    }

    $sendfax_args{files} = [];
    if($args{upload}){
        push @{$sendfax_args{files}}, eval { $args{upload}->tempname };
    }
    if($args{data}){
        $sendfax_args{input} = [\$args{data}];
    }
    my $client = new NGCP::Fax;
    $client->send_fax(\%sendfax_args);
    $c->log->debug("webfax: res=$res;");
}

sub get_fax {
    my (%args) = @_;
    my $c = $args{c};

    #moved here due to CE, as it doesn't carry NGCP::fax
    eval { require NGCP::Fax; };
    if ($@) {
        if ($@ =~ m#Can't locate NGCP/Fax.pm#) {
            $c->log->debug("Fax features are not supported in the Community Edition");
            return;
        } else {
            die $@;
        }
    }

    my ($filename, $format) = @{args}{qw(filename format)};
    return unless $filename;
    my $spool = $c->config->{faxserver}{spool_dir} || return;
    my $filepath;
    foreach my $dir (qw(completed failed)) {
        my $check_path = sprintf "%s/%s/%s", $spool, $dir, $filename;
        if (-e $check_path) {
            $filepath = $check_path;
            last;
        }
    }
    return unless $filepath;


    my $content;
    my $ext = 'tif';

    if ($format) {
        my $client = new NGCP::Fax;
        my $fh = $client->convert_file({}, $filepath, $format);
        my $rs_old = $RS;
        local $RS = undef;
        $content = <$fh>;
        local $RS = $rs_old;
        close $fh;
        $ext = $client->formats->{$format}->{extension};
    } else {
        eval { $content = read_file($filepath, binmode => ':raw'); };
        return if $@;
    }

    return ($content, $ext);
}

1;

# vim: set tabstop=4 expandtab:
