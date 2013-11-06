package Rent::PIQT::Util;

use strict;
use String::Escape qw/
    backslash
    singlequote
    unbackslash
    unsinglequote
/;
use Text::ParseWords;

BEGIN {
    String::Escape::_define_backslash_escapes(
        "'" => "'",
    );
}

our @ISA = qw/Exporter/;
our @EXPORT = qw/
    argstring_to_array
    indent_lines
    is_double_quoted
    is_quoted
    is_regexp_string
    is_single_quoted
    like_to_regexp
    normalize_single_quoted
    pluralize
    rstring_to_regexp
    strip_spaces
    undouble_quote
    unquote
    unquote_or_die
    unsingle_quote
/;
our @EXPORT_OK = ();

sub argstring_to_array {
    my ($str, %opts) = @_;
    return () unless $str;
    return quotewords('\s+', 1, $str);
}

sub indent_lines {
    my ($str, $amt) = @_;
    $amt ||= 1;
    return join("\n", map { "    " x $amt . $_ } split(/\r?\n/, $str));
}

sub is_double_quoted {
    my ($str) = @_;
    return $str =~ /^".*"$/;
}

sub is_quoted {
    my ($str) = @_;
    return is_double_quoted($str) || is_single_quoted($str);
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

sub normalize_single_quoted {
    my ($str) = @_;
    return $str unless is_single_quoted $str;
    return unbackslash unsinglequote $str;
}

sub undouble_quote {
    return unbackslash String::Escape::unquote $_[0];
}

sub unquote {
    my ($str) = @_;
    if (is_double_quoted($str)) {
        return undouble_quote($str);
    } elsif (is_single_quoted($str)) {
        return unsingle_quote($str);
    } else {
        return $str;
    }
}

sub unquote_or_die {
    my ($str) = @_;
    my $processed = unquote($str);

    die "Syntax error: expected single- or double-quoted string at:\n\n\t$str\n\t^" if $str eq $processed;
    return $processed;
}

sub unsingle_quote {
    return unsinglequote $_[0];
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
