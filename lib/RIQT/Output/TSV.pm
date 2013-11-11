package RIQT::Output::TSV;

use Moo;
use String::Escape qw/backslash/;

with 'RIQT::Output';


sub start {
    my ($self, $fields) = @_;
    $self->out->print(join("\t", map { backslash($_->{'name'}) } @$fields) . "\n");
}

sub finish {
    my ($self) = @_;
    # NOOP
}

sub record {
    my ($self, $values) = @_;
    $self->out->print(join("\t", map { backslash($_) } @$values) . "\n");
}

1;

=head1 NAME

RIQT::Output::TSV - Tab-separated values output driver for RIQT

=head1 SYNOPSIS

The first line of the output will be tab-separated column headings. Special
characters in the column headings will be escaped first, e.g., tabs inside
a column name will appear as a literal '\t', rather than a tab character.

Subsequent lines of the output will be the records, one per line.

For example, with column marker:

    12345678123456781234567812345678123456781234567812345678

    object_id       object_tp       name
    1       Property        Test property by rent.com

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
