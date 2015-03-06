package NGCP::Panel::Utils::Device;


use strict;

sub process_connectable_models{
    my ($c, $just_created, $devmod, $connectable_models) = @_;
    my $schema = $c->model('DB');
    if($connectable_models){
        my @columns = ('device_id' , 'extension_id');
        if('extension' eq $devmod->type){
        #extension can be connected to other extensions? If I remember right - yes.
            @columns = reverse @columns;
        }else{
            #we defenitely can't connect phone to phone
            my $phone2phone = $schema->resultset('autoprov_devices')->search_rs({
                'type' => 'phone',
                'id' => { 'in' => $connectable_models },
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
        foreach my $connected_id(@$connectable_models){
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
