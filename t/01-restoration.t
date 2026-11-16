use strict;
use warnings;
use Test::More;
use Digest::SHA qw(sha256_hex);
use JSON::PP qw(decode_json);
open my $manifest, '<', 'recovery/SHA256.json' or die $!;
my $expected = decode_json(do { local $/; <$manifest> });
for my $path (sort keys %$expected) {
    open my $file, '<:raw', $path or die "$path: $!";
    my $bytes = do { local $/; <$file> };
    is(sha256_hex($bytes), $expected->{$path}, "$path matches recovered baseline");
}
done_testing;
