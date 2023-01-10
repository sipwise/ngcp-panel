package NGCP::Panel::Utils::Device;

use strict;
use warnings;
use Crypt::Rijndael;
use Digest::SHA qw/sha256/;
use IO::String;

our $denwaip_masterkey = '@newrocktech2007';
our $denwaip_magic_head = "\x40\x40\x40\x24\x24\x40\x40\x40\x40\x40\x40\x24\x24\x40\x40\x40";

sub store_and_process_device_model {
    my ($c, $item, $resource) = @_;

    my $just_created = $item ? 0 : 1;

    #this deletion should be db->create
    my $linerange = delete $resource->{linerange};

    my $connectable_models = delete $resource->{connectable_models};
    my $sync_parameters = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_prefetch($c, $item, $resource);
    my $credentials = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_prefetch($c, $item, $resource);
    NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_clear($c, $resource);
    # TODO: DB errors thrown in the actions below are not caught and
    # produce a 500 error without any logs, which makes it really=
    # difficult to find the reason
    if($item){
        $item->update($resource);
        $c->model('DB')->resultset('autoprov_sync')->search_rs({
            device_id => $item->id,
        })->delete;
    }else{
        $item = $c->model('DB')->resultset('autoprov_devices')->create($resource);
    }
    NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_store($c, $item, $credentials);
    NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_store($c, $item, $sync_parameters);
    NGCP::Panel::Utils::DeviceBootstrap::dispatch_devmod($c, 'register_model', $item);
    if(defined $connectable_models) {
        NGCP::Panel::Utils::Device::process_connectable_models($c, $just_created, $item, $connectable_models);
    }
    if($just_created){
        NGCP::Panel::Utils::Device::create_device_model_ranges($c, $item, $linerange);    
    }else{
        NGCP::Panel::Utils::Device::update_device_model_ranges($c, $item, $linerange);
    }
    return $item;
}

sub create_device_model_ranges {
    my ($c, $item, $linerange) = @_;
    foreach my $range(@{ $linerange }) {
        delete $range->{id};
        $range->{num_lines} = @{ $range->{keys} }; # backward compatibility
        my $keys = delete $range->{keys};
        my $r = $item->autoprov_device_line_ranges->create($range);
        my $i = 0;
        foreach my $label(@{ $keys }) {
            $label->{line_index} = $i++;
            $label->{position} = delete $label->{labelpos};
            delete $label->{id};
            $r->annotations->create($label);
        }
    }
}

sub update_device_model_ranges {
    my ($c, $item, $linerange) = @_;
    my @existing_range = ();
    my $range_rs = $item->autoprov_device_line_ranges;
    foreach my $range(@{ $linerange }) {
        next unless(defined $range);
        if(defined $range->{id}) {
            my $range_by_id = $c->model('DB')->resultset('autoprov_device_line_ranges')->find($range->{id});
            if( $range_by_id && ( $range_by_id->device_id != $item->id ) ){
            #this is extension linerange, stop processing this linerange completely
            #we should care about it here due to backward compatibility, so API user still can make GET => PUT without excluding extension ranges
                next;
            }
        }
        my $keys = delete $range->{keys};
        $range->{num_lines} = @{ $keys }; # backward compatibility
        my $range_db;
        if(defined $range->{id}) {
            # should be an existing range, do update
            $range_db = $range_rs->find($range->{id});
            delete $range->{id};
            unless($range_db) {#really this is strange situation
                $range_db = $range_rs->create($range);
            } else {
                # formhandler only passes set check-boxes, so explicitly unset here
                $range->{can_private} //= 0;
                $range->{can_shared} //= 0;
                $range->{can_blf} //= 0;
                $range->{can_speeddial} //= 0;
                $range->{can_forward} //= 0;
                $range->{can_transfer} //= 0;
                $range_db->update($range);
            }
        } else {
            # new range
            $range_db = $range_rs->create($range);
        }
        $range_db->annotations->delete;
        my $i = 0;
        foreach my $label(@{ $keys }) {
            next unless(defined $label);
            $label->{line_index} = $i++;
            $label->{position} = delete $label->{labelpos};
            delete $label->{id};
            $range_db->annotations->create($label);
        }

        push @existing_range, $range_db->id; # mark as valid (delete others later)

        # delete field device line assignments with are out-of-range or use a
        # feature which is not supported anymore after edit
        foreach my $fielddev_line($c->model('DB')->resultset('autoprov_field_device_lines')
            ->search({ linerange_id => $range_db->id })->all) {
            if($fielddev_line->key_num >= $range_db->num_lines ||
               ($fielddev_line->line_type eq 'private' && !$range_db->can_private) ||
               ($fielddev_line->line_type eq 'shared' && !$range_db->can_shared) ||
               ($fielddev_line->line_type eq 'blf' && !$range_db->can_blf) ||
               ($fielddev_line->line_type eq 'speeddial' && !$range_db->can_speeddial) ||
               ($fielddev_line->line_type eq 'forward' && !$range_db->can_forward) ||
               ($fielddev_line->line_type eq 'transfer' && !$range_db->can_transfer)) {

               $fielddev_line->delete;
           }
        }
    }
    # delete invalid range ids (e.g. removed ones)
    $range_rs->search({
        id => { 'not in' => \@existing_range },
    })->delete_all;
}

sub process_connectable_models{
    my ($c, $just_created, $devmod, $connectable_models_in) = @_;
    my $schema = $c->model('DB');
    $connectable_models_in ||= [];
    if('ARRAY' ne ref $connectable_models_in){
        $connectable_models_in = [$connectable_models_in];
    }
    if(@$connectable_models_in){
        my $connectable_models_ids = [];
        foreach(@$connectable_models_in){
            my $name_or_id = $_;
            if( $name_or_id !~ /^\d+$/ ){
                (my($vendor,$model_name)) = $name_or_id =~ /^([^ ]+) (.*)$/;
                my $model = $schema->resultset('autoprov_devices')->search_rs({
                    'vendor' => $vendor,
                    'model'  => $model_name,
                })->first;
                if($model){
                    push @$connectable_models_ids, $model->id;
                }
            }else{
                push @$connectable_models_ids, $name_or_id;
            }
        }
        my @columns = qw(device_id extension_id);
        if('extension' eq $devmod->type){
        #extension can be connected to other extensions? If I remember right - yes.
            @columns = reverse @columns;
        }else{
            #we defenitely can't connect phone to phone
            my $phone2phone = $schema->resultset('autoprov_devices')->search_rs({
                'type' => 'phone',
                'id' => { 'in' => $connectable_models_ids },
            });
            if($phone2phone->first){
                die("Phone can't be connected to the phone as extension.");
            }
        }
        if(!$just_created){
            #we don't need to clear old relations, because we just created this device
            $schema->resultset('autoprov_device_extensions')->search_rs({
                $columns[0] => $devmod->id,
            })->delete;
        }
        foreach my $connected_id(@$connectable_models_ids){
            if($devmod->id == $connected_id){
                die("Device can't be connected to itself as extension.");
            }
            $schema->resultset('autoprov_device_extensions')->create({
                $columns[0] => $devmod->id,
                $columns[1] => $connected_id,
            });
        }
    }
}

sub denwaip_fielddev_config_process{
    my($config, $result, %params) = @_;
    my $field_device = $params{field_device};
    $result->{content} = denwaip_encrypt(${$result->{content}}, $field_device->identifier );
}

sub denwaip_encrypt{
    my ($plain, $mac) = @_;

    my $encrypted_data = IO::String->new();

    $mac = lc($mac);

    # hard coded master key
    my $key = $mac . $denwaip_masterkey;

    # file starts with a hard coded magic
    print $encrypted_data ($denwaip_magic_head);

    # generate random seed. originally SHA hash over input file path+name plus some other unknown value
    my $seed = sha256(rand() . rand() . rand());
    $seed = substr($seed, 0, 16);
    print $encrypted_data ($seed);

    # 256 iterations of sha256
    my $keybuf = $seed . ("\0" x 16);
    for (1 .. 256) {
        my $hash = sha256($keybuf . $key);
        $keybuf = $hash;
    }

    # got our AES key
    my $cipher = Crypt::Rijndael->new($keybuf, Crypt::Rijndael::MODE_ECB());

    # for final checksum
    my $xor1 = (chr(54) x 64);
    my $xor2 = (chr(92) x 64);

    substr($xor1, 0, 32) = substr($xor1, 0, 32) ^ substr($keybuf, 0, 32);
    substr($xor2, 0, 32) = substr($xor2, 0, 32) ^ substr($keybuf, 0, 32);

    # initialize checksum SHA context
    my $checksum_sha = Digest::SHA->new('sha256');
    $checksum_sha->add($xor1);

    # encrypt routine
    while ($plain ne '') {
        # each plaintext block is xor'd with the current "seed", then run through AES, then written to file

        my $plain_block = substr($plain, 0, 16, '');

        # pad block to 16 bytes. original code seems to leave contents of previous buffer unchanged
        # if block is smaller than 16 bytes -- unsure if this is a requirement
        while (length($plain_block) < 16) {
            $plain_block .= "\0";
        }

        substr($plain_block, 0, 16) = substr($plain_block, 0, 16) ^ substr($seed, 0, 16);

        my $enc_block = $cipher->encrypt($plain_block);
        print $encrypted_data ($enc_block);

        $checksum_sha->add($enc_block);
        # "seed" for the next block is the previous encrypted block
        $seed = $enc_block;
    }

    my $interim_sha = $checksum_sha->digest();
    my $checksum = sha256($xor2 . $interim_sha);
    print $encrypted_data ($checksum);

    return $encrypted_data->string_ref;
}

1;

=head1 NAME

NGCP::Panel::Utils::Device

=head1 DESCRIPTION

Different business logic method for pbx devices

=head1 METHODS

=head2 process_connectable_models

Process data tolink devices and extensions in the DB.

=head1 AUTHOR

Irina Peshinskaya C<< <ipeshinskaya@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
