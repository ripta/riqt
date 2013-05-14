package Rent::PIQT::Output;

use Moo::Role;

with 'Rent::PIQT::Component';

has 'err' => (
    is => 'ro',
    isa => sub { die "Attribute 'err' of 'Rent::PIQT::Output' must be an IO::Handle" unless ref $_[0] eq 'IO::Handle' },
    required => 1,
);
has 'out' => (
    is => 'ro',
    isa => sub { die "Attribute 'out' of 'Rent::PIQT::Output' must be an IO::Handle" unless ref $_[0] eq 'IO::Handle' },
    required => 1,
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

sub debug {
    my ($self, $msg) = @_;
    return unless $self->controller->config->verbose;
    return unless $self->controller->config->verbose >= 3;
    $self->err->print("[DEBUG] $msg\n");
}

sub error {
    my ($self, $msg) = @_;
    $self->err->print("[ERROR] $msg\n");
}

sub info {
    my ($self, $msg) = @_;
    return unless $self->controller->config->verbose;
    return unless $self->controller->config->verbose >= 2;
    $self->err->print("[INFO] $msg\n");
}

1;
