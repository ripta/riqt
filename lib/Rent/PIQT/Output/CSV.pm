package Rent::PIQT::Output::CSV;

use Moo;
use String::Escape qw/qqbackslash/;

with 'Rent::PIQT::Output';


sub start {
    my ($self, $fields) = @_;
    $self->out->print(join(",", map { qqbackslash($_{'name'}) } @$fields) . "\n");
}

sub finish {
    my ($self) = @_;
    # NOOP
}

sub record {
    my ($self, $values) = @_;
    $self->out->print(join(",", map { qqbackslash($_) } @$values) . "\n");
}

1;
