package Rent::PIQT::Output;

use Moo::Role;


# The output device, to be called from the required methods in the
# implementation subclasses.
has 'sink' => (
    is  => 'rw',
    isa => sub {
        warn "$_[0] is not an IO::Handle" unless ref $_[0] eq 'IO::Handle';
    },
);

# The start and end of output. Signatures:
#   start(\@fields)
#       [{name => ..., type => ..., length => ...}, ...]
#       where type in (str, int, float, bitflag, bool, date)
#   finish()
requires qw/start finish/;

# A single record:
#   record(\@field_values)
requires qw/record/;

1;
