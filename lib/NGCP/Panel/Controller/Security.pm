package NGCP::Panel::Controller::Security;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use XML::Mini::Document;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::XMLDispatcher;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub root :PathPart('/') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
}

sub index :Chained('/') :PathPart('security') :Args(0) {
    my ( $self, $c ) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;

    my $ip_xml = <<'EOF';
<?xml version="1.0" ?>
<methodCall>
    <methodName>htable.dump</methodName>
    <params>
        <param><value><string>ipban</string></value></param>
    </params>
</methodCall>
EOF

    my $ip_res = $dispatcher->dispatch("loadbalancer", 1, 1, $ip_xml);

    my @ips = ();
    for my $host (grep {$$_[1]} @$ip_res) {
        my $xmlDoc = XML::Mini::Document->new();
        $xmlDoc->parse($host->[2]);
        my $xmlHash = $xmlDoc->toHash();

        # non empty response
        if(defined $xmlHash->{methodResponse}->{params}->{param}->{value} and
           '' ne   $xmlHash->{methodResponse}->{params}->{param}->{value} ) {

            # single IP
            if(ref $xmlHash->{methodResponse}->{params}->{param}->{value}->{struct} eq 'HASH') {
                push @ips, { ip => $xmlHash->{methodResponse}->{params}->{param}->{value}->{struct}->{member}->[2]->{value}->{struct}->{member}->{value}->{struct}->{member}->[0]->{value}->{string} };
            }
            # multiple IPs
            else {
                for my $struct ( @{ $xmlHash->{methodResponse}->{params}->{param}->{value}->{struct} } ) {
                    push @ips, { ip => $struct->{member}->[2]->{value}->{struct}->{member}->{value}->{struct}->{member}->[0]->{value}->{string} };
                }
            }
        }
    }


    my $user_xml = <<'EOF';
<?xml version="1.0" ?>
<methodCall>
    <methodName>htable.dump</methodName>
    <params>
        <param><value><string>auth</string></value></param>
    </params>
</methodCall>
EOF

    my $user_res = $dispatcher->dispatch("loadbalancer", 1, 1, $user_xml);
    my @users = ();
    my $usr = {};
    for my $host (grep {$$_[1]} @$user_res) {
        my $xmlDoc = XML::Mini::Document->new();
        $xmlDoc->parse($host->[2]);
        my $xmlHash = $xmlDoc->toHash();

        # non empty response
        if(defined $xmlHash->{methodResponse}->{params}->{param}->{value} and
           '' ne   $xmlHash->{methodResponse}->{params}->{param}->{value} ) {

            for my $struct_ar ( @{ $xmlHash->{methodResponse}->{params}->{param}->{value}->{struct} } ) {
                # possibly buggy behaviour of kamailio to return mutliple entries as one member
                # (array of hashes) instead of seperate members (hashes)
                my $member = ref $struct_ar->{member}->[2]->{value}->{struct}->{member} eq 'HASH'
                    ? [ $struct_ar->{member}->[2]->{value}->{struct}->{member} ]
                    : $struct_ar->{member}->[2]->{value}->{struct}->{member};

                foreach my $m (@$member) {
                    $m->{value}->{struct}->{member}->[0]->{value}->{string} =~ m/(?<user>.*)::(?<key>.*)/;
                    my $username = $+{user};
                    my $key = $+{key};
                    my $value = $m->{value}->{struct}->{member}->[1]->{value}->{int};

                    # there souldn't be any other keys
                    $key eq 'auth_count' and $usr->{$username}->{auth_count} = $value;
                    $key eq 'last_auth' and $usr->{$username}->{last_auth} = $value;
                }
            }
        }

        for my $key (keys %{ $usr }) {
            push @users, {
                username => $key,
                auth_count => $usr->{$key}->{auth_count},
                last_auth => $usr->{$key}->{last_auth},
            } if($usr->{$key}->{auth_count} >= $c->config->{security}->{failed_auth_attempts});
        }
    }
    
    $c->stash(
        template => 'security/list.tt',
        banned_ips => \@ips,
        banned_users => \@users,
    );
}

sub ip_base :Chained('/') :PathPart('security/ip') :CaptureArgs(1) {
    my ( $self, $c, $ip ) = @_;
    $c->stash->{ip} = $ip;
}

sub ip_unban :Chained('ip_base') :PathPart('unban') :Args(0) {
    my ( $self, $c ) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    my $ip = $c->stash->{ip};

    my $xml = <<"EOF";
<?xml version="1.0" ?>
<methodCall>
    <methodName>htable.delete</methodName>
    <params>
        <param><value><string>ipban</string></value></param>
        <param><value><string>$ip</string></value></param>
    </params>
</methodCall>
EOF

    $dispatcher->dispatch("loadbalancer", 1, 1, $xml);

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/security'));
}

sub user_base :Chained('/') :PathPart('security/user') :CaptureArgs(1) {
    my ( $self, $c, $user ) = @_;
    $c->stash->{user} = $user;
}

sub user_unban :Chained('user_base') :PathPart('unban') :Args(0) {
    my ( $self, $c ) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    my $user = $c->stash->{user};

    my $xml = <<"EOF";
<?xml version="1.0" ?>
<methodCall>
    <methodName>htable.delete</methodName>
    <params>
        <param><value><string>auth</string></value></param>
        <param><value><string>$user</string></value></param>
    </params>
</methodCall>
EOF

    $dispatcher->dispatch("loadbalancer", 1, 1, $xml);

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/security'));
}

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
