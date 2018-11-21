package NGCP::Panel::Controller::API::SoundSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SoundSets/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines sound sets for both system and customers.';  # should allow a different description per role
};

sub query_params {
    return [
        {
            param => 'customer_id',  # should allow different params per role (no security-problem)
            description => 'Filter for sound sets of a specific customer',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'contract_id' => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for sound sets of a specific reseller',
            type => 'string_eq',
        },
        {
            param => 'name',
            description => 'Filter for sound sets with a specific name (wildcard pattern allowed)',
            type => 'string_like',
        },
    ];
}


sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item;
    try {
        my $copy_from_default_params =  { map {$_ => delete $resource->{$_}} (qw/copy_from_default loopplay replace_existing language/)};

        $item = $c->model('DB')->resultset('voip_sound_sets')->create($resource);
        if($item->contract_id && $item->contract_default) {
            $c->model('DB')->resultset('voip_sound_sets')->search({
                reseller_id => $item->reseller_id,
                contract_id => $item->contract_id,
                contract_default => 1,
                id => { '!=' => $item->id },
            })->update({ contract_default => 0 });
        }
        if ($copy_from_default_params->{copy_from_default}) {
            my $error;
            my $handles_rs = NGCP::Panel::Utils::Sounds::get_handles_rs(c => $c, set_rs => $item);
            NGCP::Panel::Utils::Sounds::apply_default_soundset_files(
                c          => $c,
                lang       => $copy_from_default_params->{language},
                set_id     => $item->id,
                handles_rs => $handles_rs,
                loopplay   => $copy_from_default_params->{loopplay},
                override   => $copy_from_default_params->{replace_existing},
                error_ref  => \$error,
            );
        }
    } catch($e) {
        $c->log->error("failed to create soundset: $e"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create soundset.");
        return;
    }

    return $item;
}

1;

# vim: set tabstop=4 expandtab:
