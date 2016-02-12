package NGCP::Panel::Utils::Fax;

use File::Temp qw/tempfile/;
use TryCatch;
use IPC::System::Simple qw/capture/;
use Data::Dumper;

sub send_fax {
    my (%args) = @_;
    my $c = $args{c};

    #moved here due to CE, as it doesn't carry NGCP::fax
    use NGCP::Fax;

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

    if($args{quality}) {#low|medium|extended
        $sendfax_args{quality} = $args{quality};
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

1;

# vim: set tabstop=4 expandtab:
