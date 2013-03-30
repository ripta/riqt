package Rent::PIQT::DB::Oracle;

use Moo;

extends "Rent::PIQT::DB";


sub sanitize {
    my ($self, $query) = @_;
    $query =~ s#[;/]\s*$##g;
    return $query;
}

1;
