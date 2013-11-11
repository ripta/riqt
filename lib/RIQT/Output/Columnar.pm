package Rent::PIQT::Output::Columnar;

use Moo;
use Text::Table;

with 'Rent::PIQT::Output';

has fields => (is => 'rw');

has record_number => (is => 'rw', default => 0);

has table => (is => 'rw');

sub sep {
    my ($self) = @_;
    $self->debugf("Unicode is " . ($self->unicode ? 'ON' : 'OFF'));
    return {
        is_sep => 1,
        title  => ($self->unicode ? " \x{2503} " : ' | '),
        body   => ($self->unicode ? " \x{2502} " : ' | '),
    };
}

sub start {
    my ($self, $fields) = @_;
    $self->fields($fields);

    my @headings = map {
        my $col_spec = {
            title   => $_->{'name'},
            align   => 'left',
        };
        ($col_spec, $self->sep)
    } @$fields;
    pop @headings if @headings;

    $self->record_number(0);

    $self->debugf("Adding heading: (%s)", join(', ', @headings));
    $self->table(Text::Table->new(@headings));
}

sub finish {
    my ($self) = @_;
    my $t = $self->table;
    $self->table(undef);
    return unless $self->record_number > 0;

    $self->debugf("Printing output table with %d lines", $t->body_height);
    $self->println;

    foreach ($t->title) {
        $self->print($_);
    }
    if ($self->unicode) {
        $self->print($t->rule("\x{2501}", "\x{2547}"));
    } else {
        $self->print($t->rule("-", "+"));
    }
    foreach ($t->body) {
        $self->print($_);
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
            $mod_values->[$idx] = $self->unicode ? "\x{2205}" : '(null)';
        }
    }

    $self->record_number($self->record_number + 1);
    $self->debugf("Added new record with %d values", scalar(@$values));
    $self->table->add(@$mod_values);
}

1;

=head1 NAME

Rent::PIQT::Output::Columnar - Column-oriented output driver for PIQT

=head1 SYNOPSIS

Output like tabular, except each column containing a newline is formatted
in the same column.

    note_id  ┃ note_tp            ┃ salesperson_id ┃ note_nm         ┃ value_xt
    ━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     9857516 │ ntp_invoiceprinted │   9669938      │ Invoice Printed │ ∅
     9857519 │ ntp_invoice_faxed  │   9669938      │ Invoice Faxed   │ Invoice Faxed. Attn: Brenda
    40116931 │ ntp_property_edit  │    954250      │ Edit Property   │ Euna Han <ehan@rent.com> (954250)
             │                    │                │                 │ made the following changes to
             │                    │                │                 │ TEST Rent.com Property (Property 427608):
             │                    │                │                 │   Property (427608):
             │                    │                │                 │     Display company name as: 0 => 4

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
