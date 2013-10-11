package NGCP::Panel::Utils::Sounds;
use strict;
use warnings;

use Sipwise::Base;
use IPC::System::Simple qw/capturex/;
use File::Temp qw/tempfile/;

sub transcode_file {
    my ($tmpfile, $source_codec, $target_codec) = @_;

    my $out;
    my @conv_args;
    
    ## quite snappy, but breaks SOAP (sigpipe's) and the catalyst devel server
    ## need instead to redirect like below

    given ($target_codec) {
        when ('PCMA') {
            @conv_args = ($tmpfile, qw/--type raw --bits 8 --channels 1 -e a-law - rate 8k/);
        }
        when ('WAV') {
            if ($source_codec eq 'PCMA') {
                # this can actually only come from inside
                # certain files will be stored as PCMA (for handles with name "music_on_hold")
                @conv_args = ( qw/-A --rate 8k --channels 1 --type raw/, $tmpfile, "--type", "wav", "-");
            }
            else {
                @conv_args = ($tmpfile, qw/--type wav --bits 16 - rate 8k/);
            }
        }
    }
    
    $out = capturex([0], "/usr/bin/sox", @conv_args);
    
    return $out;
}

sub transcode_data {
    my ($data, $source_codec, $target_codec) = @_;
    my ($fh, $filename) = tempfile;
    print $fh $data;
    close $fh;
    my $out = transcode_file($filename, $source_codec, $target_codec);
    unlink $filename; 

    return $out;
}

sub stash_soundset_list {
    my (%params) = @_;

    my $c = $params{c};
    my $contract = $params{contract}; 

    my $sets_rs = $c->model('DB')->resultset('voip_sound_sets');
    if($contract) {
        say ">>>>>>>>>>>>>>> we've a contract, limit rs";
        $sets_rs = $sets_rs->search({ 'me.contract_id' => $contract->id });
    }

    my $dt_fields = [
        { name => 'id', search => 1, title => '#' },
        { name => 'name', search => 1, title => 'Name' },
        { name => 'description', search => 1, title => 'Description' },
    ];

    if($c->user->roles eq "admin") {
        splice @{ $dt_fields }, 1, 0,
            { name => 'reseller.name', search => 1, title => 'Reseller' };
        splice @{ $dt_fields }, 2, 0,
            { name => 'contract.contact.email', search => 1, title => 'Customer' };
    } elsif($c->user->roles eq "reseller") {
        splice @{ $dt_fields }, 1, 0,
            { name => 'contract.contact.email', search => 1, title => 'Customer' };
        $sets_rs = $sets_rs->search({ reseller_id => $c->user->reseller_id });
    } elsif($c->user->roles eq "subscriberadmin" && !$contract) {
        $sets_rs = $sets_rs->search({ 'me.contract_id' => $c->user->account_id });
    }

    $c->stash->{soundset_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, $dt_fields);

    $c->stash(sets_rs => $sets_rs);

    return;
}

1;

# vim: set tabstop=4 expandtab:
