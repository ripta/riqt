package Rent::PIQT::Cache;

use Moo;

with 'Rent::PIQT::Component';

has 'namespace' => (is => 'rw', required => 0);

sub _build_key {
    my ($self, $key) = @_;
    return '' unless $key;

    return $key if $key =~ m#^/#;
    return '/' . $key unless $self->namespace;

    return $self->namespace . '/' . $key;
}

sub BUILD {
    my ($self) = @_;
    $self->{'kv'} ||= {};
    # print "Loaded Cache (", join(', ', keys %{$self->{'kv'}}), ")\n";
}

sub POSTBUILD {
    my ($self) = @_;

    $self->namespace($self->controller->db->dsn);
    $self->controller->register('load', 'load;',
        sub {
            my ($ctrl) = @_;
            $ctrl->output->info("Caching object names for tab completion...");

            if (my $objects = $ctrl->db->object_names) {
                $ctrl->cache->set('object_names', $objects);
                $ctrl->cache->set('object_ts',    time);
                $ctrl->output->okf("Loaded %d objects into cache", scalar(@{ $ctrl->cache->get('object_names') }));
            } else {
                $ctrl->output->errorf("Could not load objects: %s",
                    $ctrl->db->last_error || 'unknown error',
                );
            }

            return 1;
        },
    );
}

# delete($self, $key)
sub delete {
    my ($self, $key) = @_;
    $key = $self->_build_key($key);
    # $self->controller->output->ok("CACHE DELETE $key");
    delete $self->{'kv'}->{$key};
}

# get($self, $key)
sub get {
    my ($self, $key) = @_;
    $key = $self->_build_key($key);
    # $self->controller->output->ok("CACHE GET $key");
    return exists($self->{'kv'}->{$key}) ? $self->{'kv'}->{$key} : undef;
}

# save
sub save {
    my ($self) = @_;
}

# set($self, $key, $value)
sub set {
    my ($self, $key, $value) = @_;
    $key = $self->_build_key($key);
    # $self->controller->output->ok("CACHE SET $key $value");
    return $self->{'kv'}->{$key} = $value;
}

# touch()
sub touch {
    my ($self) = @_;
    # $self->controller->output->ok("CACHE TOUCH");
    return $self->{'kv'}->{'_touched'} = time;
}


1;
