package Rent::PIQT::Util;

use strict;
use String::Escape qw/unbackslash unsinglequote/;

our @ISA = qw/Exporter/;
our @EXPORT = qw/
    like_to_regexp
    pluralize
    rstring_to_regexp
/;
our @EXPORT_OK = @EXPORT;

sub is_regexp_string {
    my ($str) = @_;
    return $str =~ m{^(m?)/(.*)/([msixpodualgc]*)$};
}

sub is_single_quoted {
    my ($str) = @_;
    return $str =~ /^'.*'$/;
}

sub like_to_regexp {
    my ($str) = @_;
    die "Syntax error: expected single-quoted string" unless is_single_quoted($str);

    my $like = unbackslash unsinglequote $str;
    $like =~ s/%/.*/g;
    return qr/^$like$/i;
}

sub pluralize {
    my ($num, $singular, $plural) = @_;
    return defined($num) && $num == 1
            ? "1 $singular"
            : "$num $plural";
}

sub rstring_to_regexp {
    my ($str) = @_;
    my @components = is_regexp_string($str);
    die "Syntax error: expected regular expression" unless @components;

    $components[2] =~ s/i// if $components[2];
    die "Unsupported operation: m// cannot have option '$components[2]'" if $components[2];

    return qr/$components[1]/i;
}

1;
