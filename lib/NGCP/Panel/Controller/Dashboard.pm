package NGCP::Panel::Controller::Dashboard;

use warnings;
use strict;

use parent 'Catalyst::Controller';

use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Widget;

sub dashb_index :Path :Args(0) {
    my ($self, $c) = @_;

    use DDP; p $c->config->{dashboard};

    my $plugin_finder = NGCP::Panel::Widget->new;

    my $widget_templates = [];
    foreach($plugin_finder->instantiate_plugins($c, 'dashboard_widgets')) {
        $_->{instance}->handle($c); #prepare stash for values rendered by tt
        push @{ $widget_templates }, $_->{instance}->template;
    }
    $c->stash(widgets => $widget_templates);

    $c->stash(template => 'dashboard.tt');
    delete $c->session->{redirect_targets};
}

sub ajax :Path('ajax') :Args(1) {
    my ($self, $c, $exec) = @_;

    my $combined_plugin = NGCP::Panel::Widget->new;

    foreach($combined_plugin->instantiate_plugins($c, 'dashboard_widgets')) {
        #$_->{instance}->handle($c);
        $combined_plugin->load_plugin($_->{name});
    }

    my $value = undef;
    eval {
        $value = $combined_plugin->$exec($c);
    };
    if ($@) {
        $c->log->debug("error processing widget ajax request '$exec': " . $@);
    }
    $c->stash(widget_data => $value);

    $c->detach( $c->view("JSON") );
}

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
