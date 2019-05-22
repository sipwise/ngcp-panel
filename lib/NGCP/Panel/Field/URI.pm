package NGCP::Panel::Field::URI;

use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Text';
use NGCP::Panel::Utils::Subscriber;

our $class_messages = {
    'uri_format' => 'URI must be in format "username", "username@domain" or phone number',
};

sub get_class_messages  {
    my $self = shift;
    return {
        %{ $self->next::method },
        %{ $class_messages },
    };
}

apply(
    [
        {
            transform => sub { 
                lc($_[0]);
            },
        },
        {
            transform => sub {
                my ($v, $field) = @_;
                my $c = $field->form->ctx;
                return $v unless($c);

                my $sub = $c->stash->{subscriber};
                return $v unless($sub);

                $v =~ s/^sips?://;
                my ($user, $domain) = split(/\@/, $v);
                $domain = $sub->domain->domain unless($domain);
                my $uri;

                if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
                    $user = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                        c => $c, subscriber => $sub, number => $user, direction => 'callee_in',
                    );
                }
                $uri = 'sip:' . $user . '@' . $domain;

                return $uri;
            },
        },
        {
            check => sub {
                my ( $value, $field ) = @_;
                #we will not follow to rfc absolutely, so we will not check headers and uri parameters
                #but we will include all allowed characters to username
                my $domain_chars  = '[:alnum:].+:-';# "+" here is from old code, I didn't remove it
                my $unreserved_chars = '-_.!~*\'()';
                # "#" is from dtmf-digit => local-phone-number => telephone-subscriber 
                # "%" is from escaped 
                # ":" we will not separate username and password
                my $userinfo_unreserved_chars = '&=+$,;?/#%:\\';

                my ($user, $domain) = split(/\@/, $value);
                
                #https://metacpan.org/pod/URI#PARSING-URIs-WITH-REGEXP
                #my($scheme, $authority, $path, $query, $fragment) =
                #$uri =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;

                my $checked;
                if ($user && $domain) {
                    my ($proto, $user_clean, $domain_clean, $rest);
                    ($proto, $user_clean) = ($user =~/(sip[s]?:)?(.+?)$/i);
                    ($domain_clean, $rest) = split(/[^$domain_chars]+/, $domain, 2);
                    if ( $user_clean =~ m/^[[:alnum:]\Q$unreserved_chars$userinfo_unreserved_chars\E]+$/ && 
                        $domain_clean =~ m/^[$domain_chars]+$/i ) {
                        $checked = $value;
                    }
                }
                $field->value($checked)
                    if $checked;
            },
            message => sub {
                my ( $value, $field ) = @_;
                return $field->get_message('uri_format');
            },
        },
    ],
);

has '+deflate_method'  => ( default => sub { \&uri_deflate } );

sub uri_deflate {
    my ( $field, $v ) = @_;
    return unless($v);
    my $c = $field->form->ctx;
    return $v unless($c);

    my $sub = $c->stash->{subscriber};
    return $v unless($sub);

    $v =~ s/^sips?://;
    my $t;
    my ($user, $domain) = split(/\@/, $v);
    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $user = NGCP::Panel::Utils::Subscriber::apply_rewrite(
            c => $c, subscriber => $sub, number => $user, direction => 'caller_out',
        );
    }
    if($domain eq $sub->domain->domain) {
        $v = $user;
    } else {
        $v = $user . '@' . $domain;
    }
    return $v;    
}

no Moose;

__PACKAGE__->meta->make_immutable;
use namespace::autoclean;

1;

# vim: set tabstop=4 expandtab:
