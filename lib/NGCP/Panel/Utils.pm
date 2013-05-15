package NGCP::Panel::Utils;
use strict;
use warnings;

sub check_redirect_chain {
    my %params = @_;

    # TODO: check for missing fields
    my $c = $params{c};

    if($c->session->{redirect_targets} && @{ $c->session->{redirect_targets} }) {
        my $target = ${ $c->session->{redirect_targets} }[0];
        if('/'.$c->request->path eq $target->path) {
            shift @{$c->session->{redirect_targets}};
            $c->stash(close_target => ${ $c->session->{redirect_targets} }[0]);
        } else {
            $c->stash(close_target => $target);
        }
    }
}

sub check_form_buttons {
    my %params = @_;

    # TODO: check for missing fields
    my $c = $params{c};
    my $fields = $params{fields};
    my $form = $params{form};
    my $back_uri = $params{back_uri};
    my $redir_uri = $params{redir_uri};

    my $posted = ($c->request->method eq 'POST');

    if($posted && $form->field('submitid')) {
        my $val = $form->field('submitid')->value;

        if(defined $val and grep {/^$val$/} @{ $fields }) {
            my $target = '/'.$val;
            $target =~ s/\./\//g; 
            if($c->session->{redirect_targets}) {
                unshift @{ $c->session->{redirect_targets} }, $back_uri;
            } else {
                $c->session->{redirect_targets} = [ $back_uri ];
            }
            if (defined $redir_uri) {
                $c->response->redirect($redir_uri);
            } else {
                $c->response->redirect($c->uri_for($target));
            }
            return 1;
        }
    }
    return;
}

1;
# vim: set tabstop=4 expandtab:
