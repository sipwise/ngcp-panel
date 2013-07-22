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

1;

# vim: set tabstop=4 expandtab:
