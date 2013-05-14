package Rent::PIQT::Output::Tabular;

use Moo;
use String::Escape qw/printable/;

with 'Rent::PIQT::Output';

has 'field_names', (is => 'rw');
has 'field_sizes', (is => 'rw');
has 'records', (is => 'rw');

sub start {
    my ($self, $fields) = @_;

    $self->field_names([]);
    $self->field_sizes([]);
    foreach my $field (@$fields) {
        my ($name, $type, $size) = @$field{qw/name type size/};
        push @{$self->field_names}, $name;
        push @{$self->field_sizes}, length($name) || 0;
    }

    $self->records([]);
}

sub finish {
    my ($self) = @_;

    my $fmt_string;
    do {
        my @fmts = ();
        foreach (@{ $self->field_sizes }) {
            push @fmts, '%' . $_ . 's';
        }

        $fmt_string = '| ' . join(' | ', @fmts) . ' |' . "\n";
    };

    $self->out->print(sprintf($fmt_string, @{$self->field_names}));
    foreach (@{$self->records}) {
        $self->out->print(sprintf($fmt_string, @{$_}));
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
