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

# Perform custom setting up after the controller and all components are ready.
sub POSTBUILD {
    my ($self) = @_;

    # Debug information for all cache keys
    $self->controller->output->debugf("Loaded %d %s into cache: %s",
        scalar($self->KEYS),
        scalar($self->KEYS) == 1 ? 'key' : 'keys',
        join(', ', $self->KEYS),
    );

    # Set cache namespace and set a special key (/current) to the current
    # database's auth info
    $self->controller->output->debugf("Setting cache namespace to %s", $self->controller->db->auth_info);
    $self->namespace($self->controller->db->auth_info);
    $self->set('/current', $self->controller->db->auth_info);

    # Register listener for SHOW CACHE internal command, which can also take
    # a string argument to filter out the list
    $self->controller->register('show cache',
        sub {
            my ($ctrl, $args) = @_;
            my $c = $ctrl->cache;
            my $o = $ctrl->output;

            my $path;
            if ($args) {
                $path = parse_argument_string($args);
                $path = $self->_build_key($path);
            }

            $o->start(
                [
                    {name => "Name",  type => "str", length => 255},
                    {name => "Type",  type => "str", length => 10},
                    {name => "Len",   type => "int", length => 6},
                    {name => "Value", type => "str", length => 4000},
                ]
            );

            foreach my $key (sort $c->KEYS) {
                next unless $key =~ m{^/};
                next if $path && $key !~ m{^\Q$path\E};

                my $val = $c->get($key);
                if (defined $val) {
                    if (ref $val eq 'ARRAY') {
                        $o->record([$key, 'ARRAY', scalar(@$val), '']);
                    } elsif (ref $val eq 'HASH') {
                        $o->record([$key, 'HASH', scalar(keys %$val), '']);
                    } else {
                        $o->record([$key, 'SCALAR', length($val), $val]);
                    }
                } else {
                    $o->record([$key, 'SCALAR', 0, undef]);
                }
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
