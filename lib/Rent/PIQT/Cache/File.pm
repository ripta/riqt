package Rent::PIQT::Cache::File;

use Moo;

with 'Rent::PIQT::Cache';

has 'filename' => (is => 'rw', required => 1);

sub BUILDARGS {
    my ($class, $filename) = @_;
    return {
        filename => $filename
    };
}


1;
