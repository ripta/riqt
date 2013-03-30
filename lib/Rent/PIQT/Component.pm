package Rent::PIQT::Component;

use Moo::Role;

has controller => (is => 'rw', weak_ref => 1);

1;
