package NGCP::Panel::Utils::Hylafax;

use Sipwise::Base;
use File::Temp qw/tempfile/;
use TryCatch;

use Data::Dumper;

sub send_fax {
    my (%args) = @_;

    my $c = $args{c};
    my $subscriber = $args{subscriber};
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    my $sendfax = $c->config->{faxserver}->{sendfax} // '/usr/bin/sendfax';
    my @sendfax_args = ();

    my $sender = 'webfax';
    my $number;
    if($subscriber->primary_number) {
        $number = $subscriber->primary_number->cc .
                  ($subscriber->primary_number->ac // '').
                  $subscriber->primary_number->sn;
    } else {
        $number = $sender;
    }
    if($prov_subscriber->voip_fax_preference) {
        $sender = $prov_subscriber->voip_fax_preference->name;
        if($prov_subscriber->voip_fax_preference->password) {
            push @sendfax_args, '-o '.$number.':'.$prov_subscriber->voip_fax_preference->password;
        } else {
            push @sendfax_args, '-o '.$number;
        }
    } else {
        push @sendfax_args, '-o '.$number;
    }
    
    push @sendfax_args, '-h '.($c->config->{faxserver}->{ip} // '127.0.0.1');
    if($args{notify}) {
        push @sendfax_args, '-D';
        push @sendfax_args, "-f '$sender <$args{notify}>'";
    } else {
        push @sendfax_args, "-f '$sender'";
    }
    unless($args{coverpage}) {
        push @sendfax_args, '-n';
    }
    if($args{resolution}) {
        if($args{resolution} eq 'low') {
            push @sendfax_args, '-l';
        } elsif($args{resolution} eq 'medium') {
            push @sendfax_args, '-m';
        } elsif($args{resolution} eq 'extended') {
            push @sendfax_args, '-G';
        }
    }

    push @sendfax_args, '-d '.$args{destination};

    my ($fh, $filename);
    if($args{data}) {
        ($fh, $filename) = tempfile;
        unless(print $fh $args{data}) {
            my $err = $!;
            close $fh;
            unlink $filename;
            die $c->loc("Failed to write fax data to temporary file: [_1]", $err);
        }
        close $fh;
    } else {
        $filename = eval { $args{upload}->tempname };
    }
    push @sendfax_args, $filename;

    my $sa = join(' ', @sendfax_args);
    my $output = `$sendfax $sa 2>&1`;
    my $exit = $?;
    unlink $filename;

    if($exit ne '0') {
        chomp $output;
        die $output."\n";
    }
}

1;

# vim: set tabstop=4 expandtab:
