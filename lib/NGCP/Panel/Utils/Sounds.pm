package NGCP::Panel::Utils::Sounds;
use strict;
use warnings;

use IPC::System::Simple qw/capturex/;
use File::Temp qw/tempfile/;
use NGCP::Panel::Utils::Sems;
use File::Slurp;

sub transcode_file {
    my ($tmpfile, $source_codec, $target_codec) = @_;

    my $out;
    my @conv_args;
    
    ## quite snappy, but breaks SOAP (sigpipe's) and the catalyst devel server
    ## need instead to redirect like below

    SWITCH: for ($target_codec) {
        /^PCMA$/ && do {
            @conv_args = ($tmpfile, qw/--type raw --bits 8 --channels 1 -e a-law - rate 8k/);
            last SWITCH;
        };
        /^WAV$/ && do {
            if ($source_codec eq 'PCMA') {
                # this can actually only come from inside
                # certain files will be stored as PCMA (for handles with name "music_on_hold")
                @conv_args = ( qw/-A --rate 8k --channels 1 --type raw/, $tmpfile, "--type", "wav", "-");
            }
            else {
                @conv_args = ($tmpfile, qw/--type wav --bits 16 - rate 8k/);
            }
            last SWITCH;
        };
        /^MP3$/ && do {
            @conv_args = ($tmpfile, qw/--type mp3 --bits 16 - rate 8k/);
            last SWITCH;
        };
        /^OGG$/ && do {
            @conv_args = ($tmpfile, qw/--type ogg --bits 16 - rate 8k/);
            last SWITCH;
        };
        # default
    } # SWITCH
    
    $out = capturex([0], "/usr/bin/sox", @conv_args);
    
    return $out;
}

sub transcode_data {
    my ($data, $source_codec, $target_codec) = @_;
    my ($fh, $filename) = tempfile;
    print $fh (ref $data ? $$data : $data);
    close $fh;
    my $out = transcode_file($filename, $source_codec, $target_codec);
    unlink $filename; 

    return \$out;
}

sub stash_soundset_list {
    my (%params) = @_;

    my $c = $params{c};
    my $contract = $params{contract}; 

    my $sets_rs = $c->model('DB')->resultset('voip_sound_sets');
    if($contract) {
        $sets_rs = $sets_rs->search({ 'me.contract_id' => $contract->id });
    }

    my $dt_fields = [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ];

    if($c->user->roles eq "admin") {
        splice @{ $dt_fields }, 1, 0,
            { name => 'reseller.name', search => 1, title => $c->loc('Reseller') };
        splice @{ $dt_fields }, 2, 0,
            { name => 'contract.contact.email', search => 1, title => $c->loc('Customer') };
    } elsif($c->user->roles eq "reseller") {
        splice @{ $dt_fields }, 1, 0,
            { name => 'contract.contact.email', search => 1, title => $c->loc('Customer') };
        $sets_rs = $sets_rs->search({ 'me.reseller_id' => $c->user->reseller_id });
    } elsif($c->user->roles eq "subscriberadmin" && !$contract) {
        $sets_rs = $sets_rs->search({ 'me.contract_id' => $c->user->account_id });
    }

    $c->stash->{soundset_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, $dt_fields);

    $c->stash(sets_rs => $sets_rs);

    return;
}

sub get_handles_rs {
    my (%params) = @_;

    my $c = $params{c};
    my $set_rs = $params{set_rs}; 

    my $handles_rs = $c->model('DB')->resultset('voip_sound_groups')
        ->search({
        },{
            select => ['groups.name', \'handles.name', \'handles.id', 'files.filename', 'files.loopplay', 'files.codec', 'files.id'],
            as => [ 'groupname', 'handlename', 'handleid', 'filename', 'loopplay', 'codec', 'fileid'],
            alias => 'groups',
            from => [
                { groups => 'provisioning.voip_sound_groups' },
                [
                    { handles => 'provisioning.voip_sound_handles', -join_type=>'left'},
                    { 'groups.id' => 'handles.group_id'},
                ],
                [
                    { files => 'provisioning.voip_sound_files', -join_type => 'left'},
                    { 'handles.id' => { '=' => \'files.handle_id'}, 'files.set_id' => $set_rs->id},
                ],
            ],
            order_by => { -asc => 'handles.name' }
        });

    if($set_rs->contract_id) {
        $handles_rs = $handles_rs->search({
            'groups.name' => { '-in' => [qw/pbx music_on_hold digits/] }
        });
    } else {
        #$handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'pbx' } });
    }

    unless($c->config->{features}->{cloudpbx}) {
        $handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'pbx' } });
    }
    unless($c->config->{features}->{cloudpbx} || $c->config->{features}->{musiconhold}) {
        $handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'music_on_hold' } });
    }
    unless($c->config->{features}->{callingcard}) {
        $handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'calling_card' } });
    }
    unless($c->config->{features}->{mobilepush}) {
        $handles_rs = $handles_rs->search({ 'groups.name' => { '!=' => 'mobile_push' } });
    }
    return $handles_rs;
}

sub apply_default_soundset_files{
    my (%params) = @_;

    my ($c, $lang, $set_id, $handles_rs, $loopplay, $override, $error_ref) = @params{qw/c lang set_id handles_rs loopplay override error_ref/};
    
    $loopplay = $loopplay ? 1 : 0;

    my $schema = $c->model('DB');

    my $base = "/var/lib/ngcp-soundsets";
    foreach my $h($handles_rs->all) {
        my $hname = $h->get_column("handlename");
        my @paths = (
            "$base/system/$lang/$hname.wav",
            "$base/customer/$lang/$hname.wav",
            "/var/lib/asterisk/sounds/$lang/digits/$hname.wav",
        );
        my $path;
        foreach my $p(@paths) {
            if(-f $p) {
                $path = $p;
                last;
            }
        }
        next unless(defined $path);

        my $data_ref;
        my $codec = 'WAV';
        my $handle_id = $h->get_column("handleid");
        my $file_id = $h->get_column("fileid");
        my $fres;
        my $fname = basename($path);

        read_file($path, buf_ref => \$data_ref);
        unless (${data_ref}) {
            $$error_ref = "Cannot upload an empty sound file, $fname";
            die $$error_ref;
        }
        if (defined $file_id) {
            if ($override) {
                $c->log->debug("override $path as $hname for existing id $file_id");

                $fres = $schema->resultset('voip_sound_files')->find($file_id);
                $fres->update({
                        filename => $fname,
                        data => ${data_ref},
                        loopplay => $loopplay,
                    });
            } else {
                $c->log->debug("skip $path as $hname exists via id $file_id and override is not set");
            }
        } else {
            $c->log->debug("inserting $path as $hname with new id");

            $fres = $schema->resultset('voip_sound_files')
                ->create({
                    filename => $fname,
                    data => ${data_ref},
                    handle_id => $handle_id,
                    set_id => $set_id,
                    loopplay => $loopplay,
                    codec => $codec,
                });
        }

        next unless defined($fres);

        my $group_name = $fres->handle->group->name;
        NGCP::Panel::Utils::Sems::clear_audio_cache($c, $fres->set_id,
            $fres->handle->name, $group_name);
    }
}

1;

# vim: set tabstop=4 expandtab:
