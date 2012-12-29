package AI::MongoDBayes::Result;
use strict;
use utf8;
use warnings qw(all);

use Moo;
use Scalar::Util qw(looks_like_number);
use Tie::IxHash;

has results     => (is => q(ro), required => 1);
has all         => (is => q(rwp));
has top_key     => (is => q(rwp));
has top_value   => (is => q(rwp));

sub BUILD {
    my ($self) = @_;

    my @ordered =
        map { @{$_}{qw{_id value}} }
        sort { $b->{value} <=> $a->{value} }
        @{$self->results};
    tie my %ordered, q(Tie::IxHash),
        @ordered;

    $self->_set_top_key($ordered[0]);
    $self->_set_top_value($ordered[1]);

    return $self->_set_all(\%ordered);
}

use overload
    q("")       => sub { shift->top_key },
    q(0+)       => sub { shift->top_value },
    fallback    => 1;

1;
