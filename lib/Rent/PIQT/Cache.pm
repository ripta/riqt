package Rent::PIQT::Cache;

use Moo::Role;

has controller => (is => 'rw', weak_ref => 1);

requires 'get';
requires 'set';

requires 'load';
requires 'save';
requires 'touch';

sub DEMOLISH {
    my ($self) = @_;
    $self->save;
}

1;
