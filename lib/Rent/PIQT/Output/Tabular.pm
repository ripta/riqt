package Rent::PIQT::Output::Tabular;

use Moo;
use String::Escape qw/printable/;
use Time::HiRes qw/gettimeofday tv_interval/;

with 'Rent::PIQT::Output';

has 'fields', (is => 'rw');
has 'field_sizes', (is => 'rw');
has 'records', (is => 'rw');

has 'start_time', (is => 'rw');

sub start {
    my ($self, $fields) = @_;

    $self->start_time([ gettimeofday ]);
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
        $self->printlnf($fmt_string, map { $_ || '(null)' } @$record);
    }

    $self->infof("%d rows affected (%.2f seconds)",
        scalar(@{ $self->records }),
        tv_interval($self->start_time)
    ) if $self->start_time;
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
