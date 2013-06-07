package Rent::PIQT::Cache;

use Moo;

with 'Rent::PIQT::Component';

has 'namespace' => (is => 'rw', required => 0);

# Private method to build the key name based on the current namespace. Keys
# that start with a '/' are deemed to be an absolute key. Relative keys are
# prepended the namespace.
sub _build_key {
    my ($self, $key) = @_;
    return '' unless $key;

    return $key if $key =~ m#^/#;
    return '/' . $key unless $self->namespace;

    return $self->namespace . '/' . $key if $self->namespace =~ m#^/#;
    return '/' . $self->namespace . '/' . $key;
}

# Initialize internal data structures.
sub BUILD {
    my ($self) = @_;
    $self->{'kv'} ||= {};
}

# Return all keys in the cache
sub KEYS {
    my ($self) = @_;
    return keys %{ $self->{'kv'} };
}

# Set the namespace according to the database data source name.
sub POSTBUILD {
    my ($self) = @_;

    $self->controller->output->debugf("Loaded %d %s into cache: %s",
        scalar($self->KEYS),
        scalar($self->KEYS) == 1 ? 'key' : 'keys',
        join(', ', $self->KEYS),
    );

    $self->controller->output->debugf("Setting cache namespace to %s", $self->controller->db->dsn);
    $self->namespace($self->controller->db->dsn);

    $self->controller->register('show cache',
        sub {
            my ($self) = @_;
            my $c = $self->cache;
            my $o = $self->output;

            $o->start(
                [
                    {name => "Name",  type => "string", length => 255},
                    {name => "Value", type => "string", length => 4000},
                ]
            );
            foreach my $key (sort $c->KEYS) {
                $o->record([$key, $c->get($key)]);
            }
            $o->finish;

            return 1;
        }
    );
}

# Delete a key from the cache. Returns the value from the cache, or undef.
sub delete {
    my ($self, $key) = @_;
    $key = $self->_build_key($key);
    $self->controller->output->debug("CACHE DELETE $key");
    delete $self->{'kv'}->{$key};
}

# Retrieve a key from the cache, or return undef.
sub get {
    my ($self, $key) = @_;
    $key = $self->_build_key($key);
    $self->controller->output->debug("CACHE GET $key");
    return exists($self->{'kv'}->{$key}) ? $self->{'kv'}->{$key} : undef;
}

# No-op to save the cache.
sub save {
    my ($self) = @_;
    $self->controller->output->debugf(
        "CACHE SAVE (%d %s)",
        scalar($self->KEYS),
        scalar($self->KEYS) == 1 ? 'key' : 'keys',
    );
    return 1;
}

# Set the key in the cache to a specific value.
sub set {
    my ($self, $key, $value) = @_;
    $key = $self->_build_key($key);
    $self->controller->output->debug("CACHE SET $key $value");
    return $self->{'kv'}->{$key} = $value;
}

# Touch the cache to mark the cache as dirty.
sub touch {
    my ($self) = @_;
    $self->controller->output->debug("CACHE TOUCH");
    return $self->{'kv'}->{'_touched'} = time;
}


1;

=head1 NAME

Rent::PIQT::Cache - Cache component base class

=head1 SYNOPSIS

This class should not be instantiated directly, but rather should be extended

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
