package AI::MongoDBayes::Tokenizer;
use strict;
use utf8;
use warnings qw(all);

use Moo;
use Text::SpeedyFx;

has seed        => (is => q(ro), default => sub { 0xdeadbeef });
has bits        => (is => q(ro), default => sub { 18 });
has latin1      => (is => q(ro), default => sub { 0 });
has tokenizer   => (
    is          => q(ro),
    lazy        => 1,
    default     => sub {
        my ($self) = @_;
        Text::SpeedyFx->new(
            $self->seed,
            $self->latin1
                ? 8
                : $self->bits,
        );
    },
    handles => { parse => q(hash) },
);

1;
