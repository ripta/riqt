package Rent::PIQT::Config::File;

use Moo;

with 'Rent::PIQT::Config';

has 'filename' => (is => 'rw', required => 1);

sub BUILDARGS {
    my ($class, $filename) = @_;
    return {
        filename => $filename
    };
}

sub load {
}

sub save {
}


1;
