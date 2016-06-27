package NGCP::Panel::Block::Generic;

use warnings;
use strict;

use parent qw/NGCP::Panel::Block::Block/;

#we inherited get_form

sub new {
    my ( $class, %args ) = @_; 
    #die __PACKAGE__ . " is abstract" if __PACKAGE__ eq $class;
    my $self = {};
    $self->{form} = $args{form};
    $self->{template} = $args{template};
    $self->{c} = $args{form}->{ctx} or die "form context required for $class";
    return bless $self, $class;
}

sub template {
    my $self = shift;
    if ($self->{template}) {
        return $self->{template};
    }
    die "block template not overloaded in derived class and \'template\' package variable is not defined";
}

sub render {
    my ($self, $vars) = @_;
    
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
    $vars{form} = $self->{form};
    $vars{base} = $self->{c}->req->base();
    $vars{name} = $self->{c}->config->{name};
    $vars{vars} = $vars;
    
    $t->process($self->template, \%vars, \$output) or
        die "Failed to process Blocks template: ".$t->error();
    return $output;

}

1;






