package NGCP::Panel::Model::DB::Base;
#use base 'Catalyst::Model::Adaptor';
use base 'Catalyst::Model';
use NGCP::Panel::Model::DB;
use Moose;


use Carp;
use MRO::Compat;


sub COMPONENT {
    my ($class, $app, @rest) = @_;
    my $arg = {};
    if ( scalar @rest ) {
        if ( ref($rest[0]) eq 'HASH' ) {
            $arg = $rest[0];
        }
        else {
            $arg = { @rest };
        }
    }
    my $self = $class->next::method($app, $arg);

    $self->_load_adapted_class;
    return $self->_create_instance(
        $app, $class->merge_config_hashes($class->config || {}, $arg)
    );
}


sub _load_adapted_class {
    my ($self) = @_;

    croak 'need class' unless $self->{class};
    my $adapted_class = $self->{class};
    Catalyst::Utils::ensure_class_loaded($adapted_class);

    return $adapted_class;
}

sub _create_instance {
    my ($self, $app, $rest) = @_;

    my $constructor = $self->{constructor} || 'new';
    my $arg = $self->prepare_arguments($app, $rest);
    my $adapted_class = $self->{class};

    return $adapted_class->$constructor($self->mangle_arguments($arg));
}

sub prepare_arguments {
    my ($self, $app, $arg) = @_;
    return exists $self->{args} ? {
        %{$self->{args}},
        %$arg,
    } : $arg;
}

sub mangle_arguments {
    my ($self, $args) = @_;
    return $args;
}

__PACKAGE__->config( 
    class => __PACKAGE__ ,
    args  => {},
);

has 'schema' => (
    is  => 'rw',
    isa => 'NGCP::Panel::Model::DB',
);
1;