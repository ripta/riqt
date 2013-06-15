package Rent::PIQT::Util;

use strict;
use String::Escape qw/
    backslash
    singlequote
    unbackslash
    unsinglequote
    unquote
/;

our @ISA = qw/Exporter/;
our @EXPORT = qw/
    indent_lines
    is_double_quoted
    is_regexp_string
    is_single_quoted
    like_to_regexp
    parse_argument_string
    pluralize
    rstring_to_regexp
    strip_spaces
/;
our @EXPORT_OK = @EXPORT;

sub indent_lines {
    my ($str, $amt) = @_;
    $amt ||= 1;
    return join("\n", map { "    " x $amt . $_ } split(/\r?\n/, $str));
}

sub is_double_quoted {
    my ($str) = @_;
    return $str =~ /^".*"$/;
}

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

sub parse_argument_string {
    my ($str) = @_;
    if (is_double_quoted($str)) {
        return unbackslash unquote $str;
    } elsif (is_single_quoted($str)) {
        return unsinglequote $str;
    } else {
        die "Syntax error: expected single- or double-quoted string";
    }
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

sub strip_spaces {
    my ($text) = @_;
    $text =~ s/^\r?\n//g;
    $text =~ /^(\s+)/ && $text =~ s/^$1//mg;
    return $text;
}

1;
