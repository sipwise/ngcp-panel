package NGCP::Panel::Controller::Product;
use Sipwise::Base;


BEGIN { use parent 'Catalyst::Controller'; }

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub prod_list :Chained('/') :PathPart('product') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $prod_rs = $c->model('DB')->resultset('products')
        ->search({
            class => { 'not in' => ['sippeering', 'pstnpeering', 'reseller'] }
        });
    $c->stash->{product_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'name', search => 1, title => $c->loc('Name') },
    ]);

    $c->stash(
        prod_rs   => $prod_rs,
    );
}

sub ajax :Chained('prod_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{prod_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{product_dt_columns});
    $c->detach( $c->view("JSON") );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Domain - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 dom_list

basis for the domain controller

=head2 root

=head2 create

Provide a form to create new domains. Handle posted data and create domains.

=head2 search

obsolete

=head2 base

Fetch a domain by its id.

Data that is put on stash: domain, domain_result

=head2 edit

probably obsolete

=head2 delete

deletes a domain (defined in base)

=head2 ajax

Get domains and output them as JSON.

=head2 preferences

Show a table view of preferences.

=head2 preferences_base

Get details about one preference for further editing.

Data that is put on stash: preference_meta, preference, preference_values

=head2 preferences_edit

Use a form for editing one preference. Execute the changes that are posted.

Data that is put on stash: edit_preference, form

=head2 load_preference_list

Retrieves and processes a datastructure containing preference groups, preferences and their values, to be used in rendering the preference list.

Data that is put on stash: pref_groups

=head2 _sip_domain_reload

Ported from ossbss

reloads domain cache of sip proxies

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
