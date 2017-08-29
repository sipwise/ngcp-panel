package NGCP::Panel::Controller::Dashboard;

use warnings;
use strict;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

sub dashb_index :Path :Args(0) {
    my ($self, $c) = @_;

    my $db_config = $c->config->{dashboard};

    my $role = $c->user->roles;
    my $widget_templates = [];

    for my $widget_name (@{ $db_config->{$role} // [] }) {
        # will be resorted to something proper later instead of eval
        my $module = "NGCP::Panel::Widget::Dashboard::$widget_name";
        eval {
            my $file = $module =~ s|::|/|gr;
            require $file . '.pm';
            $module->import();

            if ($module->filter($c)) {
                push @{ $widget_templates }, $module->template;
            }
        };
        if ($@) {
            $c->log->debug("error loading widget '$widget_name': " . $@);
        }
    }

    $c->stash(widgets => $widget_templates);
    $c->stash(template => 'dashboard.tt');
    delete $c->session->{redirect_targets};
}

sub ajax :Path('ajax') :Args(1) {
    my ($self, $c, $exec) = @_;

    my $widget_name = $c->request->param("widget");
    my $value = undef;

    $c->log->debug("calling $exec in $widget_name");

    my $module = "NGCP::Panel::Widget::Dashboard::$widget_name";
    eval {
        my $file = $module =~ s|::|/|gr;
        require $file . '.pm';
        $module->import();

        if ($module->filter($c)) {
            $value = $module->$exec($c);
        }
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
