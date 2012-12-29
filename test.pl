#!/usr/bin/env perl
use common::sense;

use File::Find;
use File::Slurp;
use MongoDB::Connection;
use Time::HiRes qw(gettimeofday tv_interval);

use AI::MongoDBayes;

# https://cwiki.apache.org/MAHOUT/twenty-newsgroups.html
# http://people.csail.mit.edu/jrennie/20Newsgroups/20news-bydate.tar.gz

my $bayes = AI::MongoDBayes->new(
    collection => MongoDB::Connection
        ->new
        ->get_database(q(nbayes))
        ->get_collection(q(nbayes)),
    tokenizer => AI::MongoDBayes::Tokenizer->new(latin1 => 1),
);

my %confusion;

my $start = [gettimeofday];
my $total = 0;

find({
    no_chdir => 1,
    wanted => sub {
        my $file = $_;
        return if -d or not -r _ or not -s _;
        #return if $total > (2**10) * 1024;

        my $data = read_file($file, binmode => q(:mmap));
        $total += length $data;

        my $correct = $bayes->category_fix((split m{/}x, $file)[-2]);
        
        if ($ENV{TRAIN}) {
            $bayes->update($correct => $data);
        } else {
            my $ctg = $bayes->predict($data, 0);
            ++$confusion{$correct}->{$ctg};
            #say STDERR qq($correct\t$ctg);
        }
    },
}, @ARGV);

matrix($bayes->categories, \%confusion)
    unless $ENV{TRAIN};

$total /= 2 ** 20;
printf qq(%0.2f MB @ %0.2f MB/s\n),
    $total,
    $total / tv_interval($start, [gettimeofday]);

sub matrix {
    my ($categs, $confusion) = @_;
    my @categs = sort keys %{$categs};

    printf q(%5s), chr(97 + $_) for 0 .. $#categs;
    print qq(\n);
    say q(-) x (5 * @categs), q(-+);

    my $i = q(a);
    for my $x (@categs) {
        my $sum = 0;
        for my $y (@categs) {
            printf q(%5d), $confusion->{$x}{$y};
            $sum += $confusion->{$x}{$y};
        }
        printf qq( |%5d%5s = %s\n), $sum, $i++, $x;
    }

    return;
}
