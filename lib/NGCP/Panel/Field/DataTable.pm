package NGCP::Panel::Field::DataTable;
use Moose;
use Template;
extends 'HTML::FormHandler::Field';

sub build_options {
    my ($self) = @_;

    return [ 
        { label => 'Select...', value => '' },
        { label => '1', value => 1 },
        { label => '2', value => 2 },
        { label => '3', value => 3 },
        { label => '4', value => 4 },
        { label => '5', value => 5 },
        #{ label => '6', value => 6 },
    ];
}

has 'template' => ( isa => 'Str', is => 'rw' );

sub render_element {
    my ($self) = @_;
    my $output;

    

    my $vars = { 
        # url => $c->uri_for(".."), fields => [qw/id name/] 
    };
    #my $t = new Template({});

    use Data::Dumper;
    print Dumper $self->template;
    #$t->process($self->template, $vars, $output);
    return "foo"; #$output;
}
 
sub render {
    my ( $self, $result ) = @_;
    $result ||= $self->result;
    die "No result for form field '" . $self->full_name . "'. Field may be inactive." unless $result;
    my $output = $self->render_element( $result );
    return $output; #$self->wrap_field( $result, $output );
}


1;

# vim: set tabstop=4 expandtab:
