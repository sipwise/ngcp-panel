package NGCP::Panel::Block::Block;

use warnings;
use strict;

use Template;

sub new {
    my ( $class, %args ) = @_;
    die __PACKAGE__ . " is abstract" if __PACKAGE__ eq $class;
    my $self = {};
    $self->{form} = $args{form};
    $self->{c} = $args{form}->{ctx} or die "form context required for $class";
    return bless $self, $class;
}

sub form {
    my $self = shift;
    return $self->{form};
}

sub template {
    my $self = shift;
    die "block template not overloaded in derived class";
}

sub render {
    my $self = shift;
    
    my $output = '';
    
    my $t = new Template({ 
        ABSOLUTE => 1, 
        INCLUDE_PATH => [
            '/media/sf_/VMHost/ngcp-panel/share/templates',
            '/usr/share/ngcp-panel/templates',
            'share/templates',
        ],
    });

    #http://search.cpan.org/~jjnapiork/Catalyst-View-TT-0.42/lib/Catalyst/View/TT.pm
    my %vars = %{$self->{c}->stash};
    $vars{c} = $self->{c};
    $vars{base} = $self->{c}->req->base();
    $vars{name} = $self->{c}->config->{name};
    
    $t->process($self->template, \%vars, \$output) or
        die "Failed to process Blocks template: ".$t->error();
        
    return $output;

}

1;






