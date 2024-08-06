package NGCP::Panel::Utils::Sounds;
use strict;
use warnings;

use English;
use Capture::Tiny qw(capture);
use File::Temp qw/tempfile/;
use NGCP::Panel::Utils::Sems;
use NGCP::Panel::Utils::Preferences;
use File::Slurp;
use File::Basename;

sub transcode_file {
    my ($tmpfile, $source_codec, $target_codec) = @_;

    my $rc = 0;
    my ($cmd, $out, $err);
    my $is_gsm = 0;
    my @conv_args;

    # check if the wav is gsm 6.10 encoded
    if (lc($source_codec) eq 'wav') {
        $cmd = join(' ', '/usr/bin/file', $tmpfile);
        ($out, $err, $rc) = capture {
            system($cmd);
        };
        if ($out =~ /GSM 6\.10/) {
            $is_gsm = 1;
            @conv_args = (qw/--encoding gsm --type sndfile/);
        }
    }

    SWITCH: for ($target_codec) {
        /^PCMA$/ && do {
            @conv_args = (@conv_args, $tmpfile, qw/--type raw --bits 16 --channels 1 -e a-law --rate 16k -/);
            last SWITCH;
        };
        /^WAV$/ && do {
            if ($source_codec eq 'PCMA') {
                # this can actually only come from inside
                # certain files will be stored as PCMA (for handles with name "music_on_hold")
                @conv_args = (qw/-A --rate 16k --channels 1 --type raw/, $tmpfile, qw/--type wav -/);
            }
            else {
                @conv_args = (@conv_args, $tmpfile, qw/--type wav --bits 16 --rate 16k -/);
            }
            last SWITCH;
        };
        /^MP3$/ && do {
            @conv_args = (@conv_args, $tmpfile, qw/--type mp3 --rate 16k -/);
            last SWITCH;
        };
        /^OGG$/ && do {
            @conv_args = (@conv_args, $tmpfile, qw/--type ogg --rate 16k -/);
            last SWITCH;
        };
        # default
    } # SWITCH

    $cmd = join(' ', '/usr/bin/sox', '-V1', @conv_args);
    ($out, $err, $rc) = capture {
        system($cmd);
    };

    if ($rc != 0 && $err) {
        die "Cannot transcode sound file is_gsm=$is_gsm source_codec=$source_codec target_codec=$target_codec cmd=($cmd) error: $err";
    }

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
    my $fetch_parents = $params{fetch_parents} // 0;

    my $sets_rs = $c->model('DB')->resultset('voip_sound_sets')->search({
    },{
        join => 'parent',
    });

    my $dt_fields = [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
        { name => 'parent.name', search => 1, title => $c->loc('Parent') },
    ];

    if ($c->user->roles eq "admin") {
        splice @{ $dt_fields }, 1, 0,
            { name => 'reseller.name', search => 1, title => $c->loc('Reseller') };
        splice @{ $dt_fields }, 2, 0,
            { name => 'contract.contact.email', search => 1, title => $c->loc('Customer') };
        push @{ $dt_fields },
            { name => 'expose_to_customer', search => 1, title => $c->loc('Expose to Customer') };
    } elsif ($c->user->roles eq "reseller") {
        splice @{ $dt_fields }, 1, 0,
            { name => 'contract.contact.email', search => 1, title => $c->loc('Customer') };
        push @{ $dt_fields },
            { name => 'expose_to_customer', search => 1, title => $c->loc('Expose to Customer') };

        $sets_rs = $sets_rs->search({ 'me.reseller_id' => $c->user->reseller_id });
    }

    if ($contract || $c->user->roles eq "subscriberadmin") {
        my $contract = $contract;
        unless ($contract) {
            my $contract_rs = $c->stash->{contract_rs} //
                NGCP::Panel::Utils::Contract::get_contract_rs(schema => $c->model('DB'))->search_rs({
                    'me.id' => $c->user->account_id,
                });
            $contract = $contract_rs->first;
        }

        my $user_role = $c->user->roles;
        my $user_contract_id = $contract->id;

        $sets_rs = $sets_rs->search({
            -or => [
                'me.contract_id' => $contract->id,
                -and => [ 'me.contract_id' => undef,
                          'me.reseller_id' => $contract->contact->reseller_id,
                          'me.expose_to_customer' => 1,
                ],
            ],
        });
        if (!$fetch_parents) {
            $sets_rs = $sets_rs->search({
            },{
                '+select' => [ { '' => \[ "select '$user_role'" ], -as => 'user_role' },
                               { '' => \[ "select '$user_contract_id'" ], -as => 'user_contract_id' },
                               'me.contract_id' ,
                             ]
            });
        }

        push @{ $dt_fields },
            { name => 'user_role', visible => 0, search => 0, title => $c->loc('#UserRole') },
            { name => 'user_contract_id', visible => 0, search => 0, title => $c->loc('#UserContractId') },
            { name => 'contract_id', visible => 0, search => 0, title => $c->loc('#Contract_id') };
    }

    $c->stash->{soundset_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, $dt_fields);

    $c->stash(sets_rs => $sets_rs);

    return;
}

sub get_file_handles {
    my (%params) = @_;

    my $c = $params{c};
    my $set_id = $params{set_id};

    my @file_handles = ();

    my $handles_rs = $c->model('DB')->resultset('voip_sound_handles')->search({
    },{
        alias => 'handles',
        select => [
            'group.name','handles.name', 'handles.id',
        ],
        as => [
            'group_name', 'handle_name', 'handle_id',
        ],
        join => 'group',
        order_by => { -asc => 'handles.name' }
    });

    unless($c->config->{features}->{cloudpbx}) {
        $handles_rs = $handles_rs->search({ 'group.name' => { '!=' => 'pbx' } });
    }
    unless($c->config->{features}->{cloudpbx} || $c->config->{features}->{musiconhold}) {
        $handles_rs = $handles_rs->search({ 'group.name' => { '!=' => 'music_on_hold' } });
    }
    unless($c->config->{features}->{callingcard}) {
        $handles_rs = $handles_rs->search({ 'group.name' => { '!=' => 'calling_card' } });
    }
    unless($c->config->{features}->{mobilepush}) {
        $handles_rs = $handles_rs->search({ 'group.name' => { '!=' => 'mobile_push' } });
    }

    my $files_rs = $c->model('DB')->resultset('voip_sound_files')->search({
        'me.set_id' => $set_id,
    });

    my %files = ();

    foreach my $file ($files_rs->all) {
        $files{$file->handle_id} = {
            filename => $file->filename,
            loopplay => $file->loopplay,
            codec    => $file->codec,
            file_id  => $file->id,
            use_parent => $file->use_parent // 1,
        }
    }

    foreach my $handle ($handles_rs->all) {
        my %file_handle = $handle->get_inflated_columns;
        my $file = $files{$file_handle{handle_id}} // {
            filename => undef,
            loopplay => undef,
            codec    => undef,
            file_id  => undef,
            use_parent => undef,
        };
        push @file_handles, {%file_handle, %{$file}};
    }

    return \@file_handles;
}

sub apply_default_soundset_files{
    my (%params) = @_;

    my ($c, $lang, $set_id, $file_handles, $loopplay, $override, $error_ref) = @params{qw/c lang set_id file_handles loopplay override error_ref/};

    $loopplay = $loopplay ? 1 : 0;

    my $schema = $c->model('DB');

    my $base = "/var/lib/ngcp-soundsets";
    foreach my $h (@{$file_handles}) {
        my $handle_name = $h->{handle_name};
        my @paths = (
            "$base/system/$lang/$handle_name.wav",
            "$base/customer/$lang/$handle_name.wav",
            "/var/lib/asterisk/sounds/$lang/digits/$handle_name.wav",
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
        my $handle_id = $h->{handle_id};
        my $file_id = $h->{file_id};
        my $fres;
        my $fname = basename($path);

        read_file($path, buf_ref => \$data_ref);
        unless (${data_ref}) {
            $$error_ref = "Cannot upload an empty sound file, $fname";
            die $$error_ref;
        }
        if (defined $file_id) {
            if ($override) {
                $c->log->debug("override $path as $handle_name for existing id $file_id");

                $fres = $schema->resultset('voip_sound_files')->find($file_id);
                $fres->update({
                        filename => $fname,
                        data => ${data_ref},
                        loopplay => $loopplay,
                    });
            } else {
                $c->log->debug("skip $path as $handle_name exists via id $file_id and override is not set");
            }
        } else {
            $c->log->debug("inserting $path as $handle_name with new id");

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

sub contract_sound_set_propagate {
    my ($c, $contract, $value) = @_;

    for my $bill_subscriber ($contract->voip_subscribers->all) {
        my $prov_subscriber = $bill_subscriber->provisioning_voip_subscriber;
        if ($prov_subscriber) {
            &subcriber_sound_set_update_or_create($c, $prov_subscriber, $value);
        }
    }
}

sub subcriber_sound_set_update_or_create {
    my ($c, $prov_subscriber, $value) = @_;

    my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(c => $c,
        prov_subscriber => $prov_subscriber, attribute => 'contract_sound_set',
    );

    my $row = $pref_rs->first;

    if (!$row) {
        $pref_rs->create({ value => $value });
    } else {
        # Update only undefined sound set value.
        $row->update({ value => $value }) if ! defined $row->value;
    }
}


sub check_parent_chain_for_loop {
    my ($c, $set_id, $parent_id) = @_;

    return 0 if !$set_id;
    return 0 if !$parent_id;
    return 1 if $set_id == $parent_id;

    my $rs = $c->model('DB')->resultset('v_sound_set_files')->search({
        'me.set_id' => $parent_id,
    });
    if ($rs->first) {
        if (my $parent_chain = $rs->first->parent_chain) {
            my @parents = split /:/, $parent_chain;
            foreach my $chain_parent_id (@parents) {
                if ($set_id == $chain_parent_id) {
                    return 1;
                }
            }
        }
    }

    return 0;
}

sub revoke_exposed_sound_set {
    my ($c, $set_id) = @_;

    my $used_customer_sets_rs = $c->model('DB')->resultset('voip_sound_sets')->search({
        parent_id => $set_id,
        contract_id => { '!=' => undef },
    });
    $used_customer_sets_rs->update({ parent_id => undef });

    my $used_subscriber_prefs_rs = $c->model('DB')->resultset('voip_usr_preferences')->search({
        'attribute.attribute' => 'sound_set',
        value => $set_id,
    },{
        join => 'attribute',
    });
    $used_subscriber_prefs_rs->delete;
}

1;

# vim: set tabstop=4 expandtab:
