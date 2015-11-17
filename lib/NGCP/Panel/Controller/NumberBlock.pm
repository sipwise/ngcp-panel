package NGCP::Panel::Controller::NumberBlock;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use JSON qw(decode_json encode_json);
use NGCP::Panel::Form::NumberBlock::BlockAdmin;
use NGCP::Panel::Form::NumberBlock::BlockReseller;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;

sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub block_list :Chained('/') :PathPart('numberblock') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{block_rs} = $c->model('DB')->resultset('voip_number_blocks');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $c->stash->{block_rs} = $c->stash->{block_rs}->search({
            'voip_number_block_resellers.reseller_id' => $c->user->reseller_id
        },{
            join => 'voip_number_block_resellers',
        });
    } else {
        $c->stash->{block_rs} = $c->stash->{block_rs}->search({
            'voip_number_block_resellers.reseller_id' => $c->user->voip_subscriber->contract->contact->reseller_id,
        },{
            join => 'voip_number_block_resellers',
        });
    }

    $c->stash->{block_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'cc', search => 1, title => $c->loc('Country Code') },
        { name => 'ac', search => 1, title => $c->loc('Area Code') },
        { name => 'sn_prefix', search => 1, title => $c->loc('SN Prefix') },
        { name => 'sn_length', search => 1, title => $c->loc('SN Length') },
        { name => 'allocable', search => 1, title => $c->loc('Allocable?') },
    ]);
    
    $c->stash(template => 'numberblock/block_list.tt');
}

sub block_root :Chained('block_list') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
}

sub block_ajax :Chained('block_list') :PathPart('ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{block_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{block_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub block_base :Chained('block_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $block_id) = @_;

    unless($block_id && is_int($block_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid number block id detected',
            desc  => $c->loc('Invalid number block id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/numberblock'));
    }

    my $res = $c->stash->{block_rs}->find($block_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Number block does not exist',
            desc  => $c->loc('Number block does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/numberblock'));
    }
    $c->stash(block => $res);
}

sub block_create :Chained('block_list') :PathPart('create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $params->{reseller_list} = encode_json([]);;

    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::NumberBlock::BlockAdmin->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::NumberBlock::BlockReseller->new(ctx => $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $reseller_list = decode_json($form->value->{reseller_list}),
                delete $form->values->{reseller_list};
                $form->values->{authoritative} = 1; # agranig: hardcode for now, not sure of the purpose

                my $values = $form->values;
                my $num = delete $values->{e164};
                $num->{sn_prefix} = delete $num->{snbase};
                $num->{sn_length} = delete $num->{snlength};
                $num->{ac} //= '';
                $values = merge($values, $num);

                my $block = $c->stash->{block_rs}->create($values);
                foreach my $r(@{ $reseller_list }) {
                    $block->voip_number_block_resellers->create({
                        reseller_id => $r, 
                    });
                }
              
                delete $c->session->{created_objects}->{reseller};
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Number block successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create number block'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/numberblock'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub block_edit :Chained('block_base') :PathPart('edit') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;

    my $block = $c->stash->{block};
    my $posted = ($c->request->method eq 'POST');
    my $params = { $block->get_inflated_columns };
    $params->{e164}{cc} = delete $params->{ac};
    $params->{e164}{ac} = delete $params->{cc};
    $params->{e164}{snbase} = delete $params->{sn_prefix};
    $params->{e164}{snlength} = delete $params->{sn_length};
    $params = merge($params, $c->session->{created_objects});
    my @resellers = $block->search_related('voip_number_block_resellers')->get_column('reseller_id')->all;
    $params->{reseller_list} = encode_json(\@resellers);

    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::NumberBlock::BlockAdmin->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::NumberBlock::BlockReseller->new(ctx => $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $reseller_list = decode_json($form->value->{reseller_list}),
                delete $form->value->{reseller_list};
                my $values = $form->values;
                my $num = delete $values->{e164};
                $num->{sn_prefix} = delete $num->{snbase};
                $num->{sn_length} = delete $num->{snlength};
                $num->{ac} //= '';
                $values = merge($values, $num);

                $block->update($values);
                $block->search_related('voip_number_block_resellers')->delete;
                for my $r(@{ $reseller_list }) {
                    $block->search_related('voip_number_block_resellers')->create({
                        reseller_id => $r,
                    });
                }
              
                delete $c->session->{created_objects}->{reseller};
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Number block successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update number block'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/numberblock'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub block_delete :Chained('block_base') :PathPart('delete') :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    
    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub{
            $c->stash->{block}->search_related('voip_number_block_resellers')->delete;
            $c->stash->{block}->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => { $c->stash->{block}->get_inflated_columns },
            desc  => $c->loc('Number block successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete number block'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/numberblock'));
}

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
