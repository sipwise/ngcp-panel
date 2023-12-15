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

    my $schema = $c->model('DB');

    my @cols = qw/name number/;
    my @fields ;
    my @fails = ();
    my $linenum = 0;
    my @entries;

    my $no_access = 0;
    my %contract_ids;
    my %subscriber_ids;
    # check user access to owner_id
    if ($c->user->roles eq 'reseller') {
        if ($owner_id && $owner eq 'reseller' && $owner_id != $c->user->reseller_id) {
            $no_access = 1;
        } elsif ($owner eq 'contract') {
            my $found = 0;
            foreach my $row ($schema->resultset('contracts')->search({
                'contact.reseller_id' => $c->user->reseller_id,
            },{
                select => ['me.id'],
                as => ['id'],
                join => 'contact',
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            })->all) {
                my $id = $row->{id};
                if ($owner_id) {
                    if ($id == $owner_id) {
                        $found = 1;
                        last;
                    }
                } else {
                    $contract_ids{$id} = 1;
                }
            }
            if ($owner_id) {
                $no_access = 1 unless $found;
            }
        } elsif ($owner eq 'subscriber') {
            my $found = 0;
            foreach my $row ($schema->resultset('voip_subscribers')->search({
                'contact.reseller_id' => $c->user->reseller_id,
            },{
                select => ['me.id'],
                as => ['id'],
                join => { 'contract' => 'contact' },
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            })->all) {
                my $id = $row->{id};
                if ($owner_id) {
                    if ($id == $owner_id) {
                        $found = 1;
                        last;
                    }
                } else {
                    $subscriber_ids{$id} = 1;
                }
            }
            if ($owner_id) {
                $no_access = 1 unless $found;
            }
        }
    } elsif ($c->user->roles eq 'subscriberadmin') {
        if ($owner_id && $owner eq 'reseller') {
            $no_access = 1;
        } elsif ($owner_id && $owner eq 'contract' && $owner_id != $c->user->account_id) {
            $no_access = 1;
        } elsif ($owner eq 'subscriber') {
            my $found = 0;
            foreach my $row ($schema->resultset('voip_subscribers')->search({
                'contract_id' => $c->user->account_id,
            },{
                select => ['me.id'],
                as => ['id'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            })->all) {
                my $id = $row->{id};
                if ($owner_id) {
                    if ($id == $owner_id) {
                        $found = 1;
                        last;
                    }
                } else {
                    $subscriber_ids{$id} = 1;
                }
            }
            if ($owner_id) {
                $no_access = 1 unless $found;
            }
        }
    } elsif ($owner_id && $c->user->roles eq 'subscriber') {
        if ($owner eq 'reseller') {
            $no_access = 1;
        } elsif ($owner eq 'contract') {
            $no_access = 1;
        } elsif ($owner eq 'subscriber' && $owner_id != $c->user->voip_subscriber->id) {
            $no_access = 1;
        }
    }

    if ($no_access) {
        my $accepted = 0;
        my (@entries, @fails);
        my $text = 'Phonebook entries upload failed: ';
           $text .= "user does not have access to $owner with id $owner_id\n";
        return (\@entries, \@fails, \$text);
    }

    $schema->txn_do(sub {

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

            if ($owner_id) {
                # name,number
                if ($owner ne 'subscriber' && scalar @fields >= 2) {
                    @{$row}{@cols} = splice @fields, 0, 2;
                # name,number,shared
                } elsif ($owner eq 'subscriber' && scalar @fields >= 3) {
                    my $shared = int($fields[2]);
                    if ($shared != 1 && $shared != 0) {
                        push @fails, $linenum;
                        next;
                    }
                    @{$row}{@cols,'shared'} = splice @fields, 0, 3;
                } else {
                    push @fails, $linenum;
                    next;
                }
                $row->{$owner.'_id'} = $owner_id;
            } else {
                if ($owner eq 'reseller') {
                    # name,number,reseller_id
                    if (scalar @fields != 3) {
                        push @fails, $linenum;
                        next;
                    }
                    my $reseller_id_f = int($fields[2]);
                    if ($c->user->roles eq 'admin') {
                        @{$row}{@cols,'reseller_id'} = @fields;
                    } elsif ($c->user->roles eq 'reseller' &&
                             $reseller_id_f == $c->user->reseller_id) {
                        @{$row}{@cols,'reseller_id'} = @fields;
                    } else {
                        push @fails, $linenum;
                        next;
                    }
                } elsif ($owner eq 'contract') {
                    # name,number,contract_id
                    if (scalar @fields != 3) {
                        push @fails, $linenum;
                        next;
                    }
                    my $contract_id_f = int($fields[2]);
                    if ($c->user->roles eq 'admin') {
                        @{$row}{@cols,'contract_id'} = @fields;
                    } elsif ($c->user->roles eq 'reseller' &&
                             exists $contract_ids{$contract_id_f}) {
                        @{$row}{@cols,'contract_id'} = @fields;
                    } elsif ($c->user->roles eq 'subscriberadmin' &&
                             $contract_id_f == $c->user->account_id) {
                        @{$row}{@cols,'contract_id'} = @fields;
                    } else {
                        push @fails, $linenum;
                        next;
                    }
                } elsif ($owner eq 'subscriber') {
                    # name,number,shared,subscriber_id
                    if (scalar @fields != 4) {
                        push @fails, $linenum;
                        next;
                    }
                    my $subscriber_id_f = int($fields[3]);
                    my $shared = int($fields[2]);
                    if ($shared != 1 && $shared != 0) {
                        push @fails, $linenum;
                        next;
                    }
                    if ($c->user->roles eq 'admin') {
                        @{$row}{@cols,'shared','subscriber_id'} = @fields;
                    } elsif ($c->user->roles eq 'reseller' &&
                             exists $subscriber_ids{$subscriber_id_f}) {
                        @{$row}{@cols,'shared','subscriber_id'} = @fields;
                    } elsif ($c->user->roles eq 'subscriberadmin' &&
                             exists $subscriber_ids{$subscriber_id_f}) {
                        @{$row}{@cols,'shared','subscriber_id'} = @fields;
                    } elsif ($c->user->roles eq 'subscriber' &&
                             $subscriber_id_f == $c->user->voip_subscriber->id) {
                        @{$row}{@cols,'shared','subscriber_id'} = @fields;
                    } else {
                        push @fails, $linenum;
                        next;
                    }
                } else {
                    push @fails, $linenum;
                    next;
                }
            }

            unless ($purge) {
                try {
                    $rs->update_or_create($row,{key=>'rel_u_idx'});
                } catch($e) {
                    push @fails, $linenum;
                    next;
                }
            }
            push @entries, $row;
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
    my ($c, $rs, $owner) = @_;

    my @cols = qw/name number/;

    if ($owner eq 'reseller' && $c->user->roles eq 'admin') {
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
