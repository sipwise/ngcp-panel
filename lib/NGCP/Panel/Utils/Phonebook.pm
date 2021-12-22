package NGCP::Panel::Utils::Phonebook;
use strict;
use warnings;

use Sipwise::Base;
use English;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::Message;

sub get_reseller_phonebook {
    my ($c, $reseller_id) = @_;
    my @pb;

    my $r_pb_rs = $c->model('DB')->resultset('reseller_phonebook')->search({
        reseller_id => $reseller_id,
    });

    for my $r ($r_pb_rs->all) {
        push @pb, { name => $r->name, number => $r->number };
    }

    return [ sort { $a->{name} cmp $b->{name} } @pb ];
}

sub get_contract_phonebook {
    my ($c, $contract_id) = @_;
    my @pb;
    my %c_numbers;

    my $contract = $c->model('DB')->resultset('contracts')->search({
        id => $contract_id,
    })->first;

    my $r_pb_rs = $c->model('DB')->resultset('reseller_phonebook')->search({
        reseller_id => $contract->contact->reseller->id,
    });

    my $c_pb_rs = $c->model('DB')->resultset('contract_phonebook')->search({
        contract_id => $contract_id,
    });

    for my $r ($c_pb_rs->all) {
        push @pb, { name => $r->name, number => $r->number };
        $c_numbers{$r->number} = $r->name;
    }

    for my $r ($r_pb_rs->all) {
        unless (exists $c_numbers{$r->number}) {
            push @pb, { name => $r->name, number => $r->number };
        }
    }

    return [ sort { $a->{name} cmp $b->{name} } @pb ];
}

sub get_subscriber_phonebook {
    my ($c, $subscriber_id) = @_;
    my @pb;
    my %c_numbers;

    my $sub = $c->model('DB')->resultset('voip_subscribers')->search({
        id => $subscriber_id,
    })->first;

    my $r_pb_rs = $c->model('DB')->resultset('reseller_phonebook')->search({
        reseller_id => $sub->contract->contact->reseller->id,
    });

    my $c_pb_rs = $c->model('DB')->resultset('contract_phonebook')->search({
        contract_id => $sub->contract_id,
    });

    my $a_pb_rs = $c->model('DB')->resultset('subscriber_phonebook')->search({
        shared => 1,
        'contract.id' => $sub->contract_id,
    },{
        join => { 'subscriber' => 'contract' },
    });

    my $s_pb_rs = $c->model('DB')->resultset('subscriber_phonebook')->search({
        subscriber_id => $subscriber_id,
    });

    for my $r ($s_pb_rs->all) {
        push @pb, { name => $r->name, number => $r->number };
        $c_numbers{$r->number} = $r->name;
    }

    for my $r ($c_pb_rs->all) {
        unless (exists $c_numbers{$r->number}) {
            push @pb, { name => $r->name, number => $r->number };
            $c_numbers{$r->number} = $r->name;
        }
    }

    for my $r ($a_pb_rs->all) {
        unless (exists $c_numbers{$r->number}) {
            push @pb, { name => $r->name, number => $r->number };
            $c_numbers{$r->number} = $r->name;
        }
    }

    for my $r ($r_pb_rs->all) {
        unless (exists $c_numbers{$r->number}) {
            push @pb, { name => $r->name, number => $r->number };
        }
    }

    return [ sort { $a->{name} cmp $b->{name} } @pb ];
}

sub ui_upload_csv {
    my ($c, $rs, $form, $owner, $owner_id, $action, $back) = @_;

    my $upload = $c->req->upload('upload_phonebook');
    my $posted = $c->req->method eq 'POST';
    my @params = ( upload_phonebook => $posted ? $upload : undef, );
    $form->process(
        posted => $posted,
        params => { @params },
        action => $action,
    );
    if($form->validated) {
        unless($upload) {
            NGCP::Panel::Utils::Message::error(
                c    => $c,
                desc => $c->loc('No phonebook entries file specified!'),
            );
            $c->response->redirect($back);
            return;
        }
        my $data = $upload->slurp;
        my($entries, $fails, $text_success);
        try {
            my ($entries, $fails, $text) =
                upload_csv($c, $rs, $owner, $owner_id,
                           $c->req->params->{purge_existing}, \$data);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $$text,
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to upload Phonebook entries'),
            );
        }

        $c->response->redirect($back);
    }

    return;
}

sub upload_csv {
    my ($c, $rs, $owner, $owner_id, $purge, $data) = @_;

    my $csv = Text::CSV_XS->new({ allow_whitespace => 1, binary => 1, keep_meta_info => 1 });

    my @cols = qw/name number/;
    my @fields ;
    my @fails = ();
    my $linenum = 0;
    my @entries;

    $c->model('DB')->txn_do(sub {

        open(my $fh, '<:encoding(utf8)', $data);

        while ( my $line = <$fh> ){
            ++$linenum;
            next unless length $line;
            unless($csv->parse($line)) {
                push @fails, $linenum;
                next;
            }
            @fields = $csv->fields();

            my $row = {};
            # name,number
            if (scalar @fields == 2) {
                @{$row}{@cols} = @fields;
            # name,number,reseller_id (in case of admin uploads)
            } elsif ($c->user->roles eq "admin" &&
                     $owner eq 'reseller' && scalar @fields == 3) {
                @{$row}{@cols,'reseller_id'} = @fields;
            # name,number,shared
            } elsif ($owner eq 'subscriber' && scalar @fields == 3) {
                @{$row}{@cols,'shared'} = @fields;
            # hmmm
            } else {
                push @fails, $linenum;
                next;
            }
            $row->{$owner.'_id'} //= $owner_id;
            push @entries, $row;
            unless ($purge) {
                $rs->update_or_create($row,{key=>'rel_u_idx'});
            }
        }

        if ($purge) {
            my ($start, $end);
            $start = time;
            $rs->delete;
            $end = time;
            $c->log->debug("Purging phonebook entries took " . ($end - $start) . "s");
            $start = time;
            $rs->populate(\@entries);
            $end = time;
            $c->log->debug("Populating phonebook entries took " . ($end - $start) . "s");
        }
    });

    my $text = $c->loc('Phonebook entries successfully uploaded');
    if (@fails) {
        $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
    }

    return ( \@entries, \@fails, \$text );
}

sub download_csv {
    my ($c, $rs, $owner, $owner_id) = @_;

    my @cols = qw/name number/;

    if ($owner eq 'admin') {
        push @cols, 'reseller_id';
    } elsif ($owner eq 'subscriber') {
        push @cols, 'shared';
    }

    my ($start, $end);
    $start = time;
    foreach my $row ($rs->all) {
        my %entry = $row->get_inflated_columns;
        delete $entry{id};
        $c->res->write_fh->write(join (",", @entry{@cols}) );
        $c->res->write_fh->write("\n");
    }
    $c->res->write_fh->close;
    $end = time;
    $c->log->debug("Creating phonebook entries CSV for download took " . ($end - $start) . "s");
    return 1;
}

1;

=head1 NAME

NGCP::Panel::Utils::Phonebook

=head1 DESCRIPTION

A helper to manipulate the phonebook data

=head1 METHODS

=head2 get_reseller_phonebook

=head2 get_contract_phonebook

=head2 get_subscriber_phonebook

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
