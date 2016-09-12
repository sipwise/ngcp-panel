package NGCP::Panel::Utils::Device;

use strict;
use warnings;
use Crypt::Rijndael;
use Digest::SHA qw/sha256/;
use IO::String;

our $denwaip_masterkey = '@newrocktech2007';
our $denwaip_magic_head = "\x40\x40\x40\x24\x24\x40\x40\x40\x40\x40\x40\x24\x24\x40\x40\x40";

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
        my @columns = ('device_id' , 'extension_id');
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

=pod
sub denwaip_decrypt{
    my ($crypted, $mac) = @_;

    my $plain_data = IO::String->new();
    
    $mac = lc($mac);

    # hard coded master key
    my $key = $mac . $denwaip_masterkey;

    # file starts with a hard coded magic
    my $magic = substr($crypted, 0, 16, '');
    $denwaip_magic_head eq "\x40\x40\x40\x24\x24\x40\x40\x40\x40\x40\x40\x24\x24\x40\x40\x40" or die "Wrong denwaip crypted data format.";

    # "random" seed taken from file
    my $seed = substr($crypted, 0, 16, '');

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

    # remove trailing checksum from buffer
    my $final_checksum = substr($crypted, -32, 32, '');

    # initialize checksum SHA context
    my $checksum_sha = Digest::SHA->new('sha256');
    $checksum_sha->add($xor1);

    # decrypt routine
    while ($crypted ne '') {
        # each plaintext block is xor'd with the current "seed", then run through AES, then written to file

        my $block = substr($crypted, 0, 16, '');
        $checksum_sha->add($block);

        my $dec_block = $cipher->decrypt($block);
        substr($dec_block, 0, 16) = substr($dec_block, 0, 16) ^ substr($seed, 0, 16);
        print $plain_data ($dec_block);

        # "seed" for the next block is the previous encrypted block
        $seed = $block;
    }

    my $interim_sha = $checksum_sha->digest();
    my $checksum = sha256($xor2 . $interim_sha);
    $final_checksum eq $checksum or die "Denwaip checksum failed.";
    return $plain_data->string_ref; 
}
=cut
1;

=head1 NAME

NGCP::Panel::Utils::Device

=head1 DESCRIPTION

Diffrent business logic method for pbx devices

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
