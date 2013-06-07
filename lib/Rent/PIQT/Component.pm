package Rent::PIQT::Component;

use Moo::Role;
use String::Escape qw/backslash printable qqbackslash quote/;

has controller => (is => 'rw', weak_ref => 1);

1;
