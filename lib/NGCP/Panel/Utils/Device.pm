package NGCP::Panel::Utils::Device;


use strict;

sub process_connectable_models{
    my ($c, $just_created, $devmod, $connectable_models) = @_;
    my $schema = $c->model('DB');
    if($connectable_models){
        my @columns = ('device_id' , 'extension_id');
        if('extension' eq $devmod->type){
            @columns = reverse @columns;
        }
        if(!$just_created){
            #we don't need to clear old relations, because we just created this device
            $schema->resultset('autoprov_device_extensions')->search_rs({
                $columns[0] => $devmod->id,
            })->delete;
        }
        foreach my $connected_id(@$connectable_models){
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
