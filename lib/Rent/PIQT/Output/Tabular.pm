package Rent::PIQT::Output::Tabular;

use Moo;
use String::Escape qw/printable/;
use Time::HiRes qw/gettimeofday tv_interval/;

with 'Rent::PIQT::Output';

has 'fields', (is => 'rw');
has 'field_sizes', (is => 'rw');
has 'records', (is => 'rw');

sub start {
    my ($self, $fields) = @_;

    $self->fields([ @$fields ]);
    $self->records([ ]);

    $self->field_sizes([ ]);
    foreach my $field (@$fields) {
        my ($name, $type, $size) = @$field{qw/name type size/};
        push @{ $self->field_sizes }, length($name) || 0;
    }
}

sub finish {
    my ($self) = @_;

    my $fmt_string = "";
    my @seps = ();
    do {
        my @fmts = ();
        foreach (@{ $self->field_sizes }) {
            push @fmts, '%-' . $_ . 's';
            push @seps, '=' x $_;
        }

        $fmt_string = join(' ', @fmts);
    };

    $self->println;
    $self->printlnf($fmt_string, map { $_->{'name'} } @{ $self->fields });
    $self->printlnf($fmt_string, @seps);
    foreach my $record (@{$self->records}) {
        $self->printlnf($fmt_string, map { defined($_) ? $_ : '(null)' } @$record);
    }

}

sub record {
    my ($self, $values) = @_;
    push @{$self->records}, $values;

    foreach my $idx (0..$#$values) {
        if (defined $values->[$idx]) {
            if (length($values->[$idx]) > $self->field_sizes->[$idx]) {
                $self->field_sizes->[$idx] = length($values->[$idx]);
            }
        } else {
            if (length('(null)') > $self->field_sizes->[$idx]) {
                $self->field_sizes->[$idx] = length('(null)');
            }
        }
    }
}

1;

=head1 NAME

Rent::PIQT::Output::Tabular - Table-oriented output driver for PIQT

=head1 SYNOPSIS

Each record is displayed in one line. Special characters in each column is escaped.

    object_id   1
    object_tp   Property
    name        Test property by rent.com

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
