package NGCP::Panel::Cache::Serializer;
use Sipwise::Base;
use Sereal::Decoder qw();
use Sereal::Encoder qw();

sub serialize {
    my ($self, $data) = @_;
    return Sereal::Encoder::encode_sereal($data);
}

sub deserialize {
    my ($self, $sereal) = @_;
    return Sereal::Decoder::decode_sereal($sereal);
}
