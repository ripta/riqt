package RIQT::Output::Tabular;

use Moo;
use String::Escape qw/printable/;
use Time::HiRes qw/gettimeofday tv_interval/;

with 'RIQT::Output';

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
                push @fmt_rec,  '%' . $self->field_sizes->[$idx] . 's';
            } elsif ($type eq 'bool') {
                push @fmt_head, '%-' . $self->field_sizes->[$idx] . 's';
                push @fmt_rec,  '%-' . $self->field_sizes->[$idx] . 's';
            } else {
                # bitflag, date
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
        $self->printlnf($fmt_rec, @$record);
    }

}

sub record {
    my ($self, $values) = @_;
    my $mod_values = [];

    foreach my $idx (0..$#$values) {
        if (defined $values->[$idx]) {
            if ($self->fields->[$idx]->{'type'} eq 'bool') {
                $mod_values->[$idx] = $values->[$idx] ? 'YES' : 'NO';
            } else {
                $mod_values->[$idx] = $values->[$idx];
            }
        } else {
            $mod_values->[$idx] = '(null)';
        }
    }

    foreach my $idx (0..$#$mod_values) {
        if (length($mod_values->[$idx]) > $self->field_sizes->[$idx]) {
            $self->field_sizes->[$idx] = length($mod_values->[$idx]);
        }
    }

    push @{$self->records}, $mod_values;
}

1;

=head1 NAME

RIQT::Output::Tabular - Table-oriented output driver for RIQT

=head1 SYNOPSIS

Each record is displayed in one line. Special characters in each column is escaped.

    object_id   1
    object_tp   Property
    name        Test property by rent.com

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
