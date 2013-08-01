package NGCP::Panel::Utils::Navigation;

use Sipwise::Base;
use DBIx::Class::Exception;
use URI::Encode qw(uri_decode);

sub check_redirect_chain {
    my %params = @_;

    # TODO: check for missing fields
    my $c = $params{c};
    $c->session->{redirect_targets} = []
        unless(defined $c->session->{redirect_targets});

    if($c->request->params->{back}) {
        my $back_uri = URI->new(uri_decode($c->request->params->{back}));
        $back_uri->query_param_delete('back');
        delete $c->request->params->{back};
        if($c->session->{redirect_targets}) {
            unshift @{ $c->session->{redirect_targets} }, $back_uri;
        } else {
            $c->session->{redirect_targets} = [ $back_uri ];
        }
    }

    if(@{ $c->session->{redirect_targets} }) {
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
    $back_uri->query_param_delete('back');
    
    $fields = { map {($_, undef)} @$fields }
        if (ref($fields) eq "ARRAY");

    my $posted = ($c->request->method eq 'POST');
    delete $form->params->{save} if $posted;
    delete $form->values->{save} if $posted;

    if($posted && $form->field('submitid')) {
        my $val = $form->value->{submitid};
        delete $form->params->{submitid};
        delete $form->values->{submitid};
        if(defined $val and exists($fields->{$val}) ) {
            my $target;
            if (defined $fields->{$val}) {
                $target = $fields->{$val};
            } else {
                $target = '/'.$val;
                $target =~ s/\./\//g;
                $target = $c->uri_for($target);
            }
            if($c->session->{redirect_targets}) {
                unshift @{ $c->session->{redirect_targets} }, $back_uri;
            } else {
                $c->session->{redirect_targets} = [ $back_uri ];
            }
            $c->response->redirect($target);
            $c->detach;
        }
    }
}

sub back_or {
    my ($c, $alternative_target) = @_;
    my $target = $c->stash->{close_target} || $alternative_target || $c->req->uri;
    $c->response->redirect($target);
    $c->detach;
}

1;

=head1 NAME

NGCP::Panel::Utils::Navigation

=head1 DESCRIPTION

A temporary helper to manipulate subscriber data

=head1 METHODS

=head2 check_redirect_chain

Sets close_target to the next uri in our redirect_chain if it exists.
Puts close_target to stash, which will be read by the templates.

=head2 check_form_buttons

Parameters:
    c
    fields - either an arrayref of fieldnames or a hashref with fieldnames
        key and redirect target as value (where it should redirect to)
    form
    back_uri - the uri we come from

Checks the hidden field "submitid" and redirects to its "value" when it
matches a field.

=head1 AUTHOR

Andreas Granig,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
