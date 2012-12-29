package AI::MongoDBayes;
use strict;
use utf8;
use warnings qw(all);

use Moo;

use AI::MongoDBayes::Result;
use AI::MongoDBayes::Tokenizer;
use MongoDB::Code;

has categories  => (is => q(rwp), default => sub { {} });
has collection  => (is => q(ro), required => 1);
has db          => (
    is          => q(ro),
    lazy        => 1,
    default     => sub {
        ## no critic (ProtectPrivateSubs)
        shift->collection->_database;
    },
);

has js_map      => (
    is          => q(ro),
    lazy        => 1,
    default     => sub {
        return MongoDB::Code->new(code => <<'EOMAP'
            function () {
                var weight = weighted
                    ? doc[0 + this._id]
                    : 1;

                for (var ctg in categ) {
                    var prob = Math.log(
                        this.ctg.hasOwnProperty(ctg)
                            ? this.ctg[ctg]
                            : 1.18e-38
                    );
                    prob -= Math.log(this.total);
         
                    emit(ctg, prob * weight);
                }
            }
EOMAP
        );
    },
);

has js_reduce   => (
    is          => q(ro),
    lazy        => 1,
    default     => sub {
        return MongoDB::Code->new(code => <<'EOREDUCE'
            function (key, values) {
                var result = 0;
                for (var i = 0; i < values.length; i++)
                    result += values[i];
                return result;
            }
EOREDUCE
        );
    },
);

has tokenizer   => (
    is          => q(ro),
    lazy        => 1,
    default     => sub { AI::MongoDBayes::Tokenizer->new },
);

sub BUILD {
    my ($self) = @_;

    $self->_categories_sync;

    return;
}

sub _categories_sync {
    my ($self) = @_;

    my $res = $self->collection->find_one({ _id => 0 });
    $self->_set_categories($res->{ctg})
        if q(HASH) eq ref $res and q(HASH) eq ref $res->{ctg};

    return $self->categories;
}

sub category_fix {
    local $_ = pop;
    s/\W/_/gisx;
    return $_;
}

sub update {
    my ($self, $category, $data) = @_;

    $self->category_fix($category);

    my $document = $self->tokenizer->parse($data);
    my $n = 0;
    while (my ($token, $count) = each %{$document}) {
        $count += 0;
        ++$n;
        $self->collection->update(
            { _id       => 0 + $token },
            { q($inc)   => { total => $count, qq(ctg.$category) => $count } },
            { upsert    => 1 },
        );
    }

    $self->categories->{$category} += $n;
    $self->collection->update(
        { _id       => 0 },
        { q($inc)   => { qq(ctg.$category) => $n } },
        { upsert    => 1 },
    );

    return;
}
 
sub predict {
    my ($self, $data, $nonweighted) = @_;
    my $weighted = not $nonweighted;

    $self->_categories_sync;

    my $document = $self->tokenizer->parse($data);
    my $res = $self->db->run_command(Tie::IxHash->new(
        mapreduce   => $self->collection->name,
        out         => { inline => 1 },
        query       => {
            _id     => {
                q($in) => [ map { 0 + $_ } keys %{$document} ],
            },
        },
        scope       => {
            categ   => $self->categories,
            doc     => $weighted ? $document : {},
            weighted=> $weighted,
        },
        map         => $self->js_map,
        reduce      => $self->js_reduce,
    ));

    $res = { results => [] }
        if q(HASH) ne ref $res or q(ARRAY) ne ref $res->{results};

    return AI::MongoDBayes::Result->new(results => $res->{results});
}

1;
