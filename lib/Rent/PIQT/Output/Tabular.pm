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

    my $fmt_head = "";
    my $fmt_rec  = "";
    my @seps = ();
    do {
        my @fmt_head = ();
        my @fmt_rec  = ();
        foreach my $idx (0..$#{ $self->field_sizes}) {
            my $type = lc $self->fields->[$idx]->{'type'};
            if ($type eq 'str') {
                push @fmt_head, '%-' . $self->field_sizes->[$idx] . 's';
                push @fmt_rec,  '%-' . $self->field_sizes->[$idx] . 's';
            } elsif ($type eq 'int') {
                push @fmt_head, '%' . $self->field_sizes->[$idx] . 's';
                push @fmt_rec,  '%' . $self->field_sizes->[$idx] . 's';
            } elsif ($type eq 'float') {
                push @fmt_head, '%' . $self->field_sizes->[$idx] . 's';
                push @fmt_rec,  '%' . $self->field_sizes->[$idx] . 'f';
            } else {
                # bitflag, bool, date
                push @fmt_head, '%-' . $self->field_sizes->[$idx] . 's';
                push @fmt_rec,  '%-' . $self->field_sizes->[$idx] . 's';
            }

            push @seps, '=' x $self->field_sizes->[$idx];
        }

        $fmt_head = join(' ', @fmt_head);
        $fmt_rec  = join(' ', @fmt_rec);
    };

    $self->println;
    $self->printlnf($fmt_head, map { $_->{'name'} } @{ $self->fields });
    $self->printlnf($fmt_head, @seps);
    foreach my $record (@{$self->records}) {
        $self->printlnf($fmt_rec, map { defined($_) ? $_ : '(null)' } @$record);
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
