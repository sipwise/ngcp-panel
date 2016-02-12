package NGCP::Panel::Utils::Hylafax;

use NGCP::Fax;
use File::Temp qw/tempfile/;
use TryCatch;
use IPC::System::Simple qw/capture/;
use Data::Dumper;

sub send_fax {
    my (%args) = @_;
    my $c = $args{c};

    my $subscriber = $args{subscriber};
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    my %sendfax_args = ();

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

    if($args{resolution}) {#low|medium|extended
        $sendfax_args{resolution} = $args{resolution};
    }

    $sendfax_args{files} = [];
    if($args{upload}){
        push @{$sendfax_args{files}}, eval { $args{upload}->tempname };
    }
    if($args{data}){
        $sendfax_args{input} = $args{data};
    }
    my $client = new NGCP::Fax;
    $client->send_fax(\%data);
}

1;

# vim: set tabstop=4 expandtab:
