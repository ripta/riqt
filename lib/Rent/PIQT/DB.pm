package Rent::PIQT::DB;

use Moo::Role;

with 'Rent::PIQT::Component';

has 'database' => (
    is => 'rw',
);

has 'driver' => (
    is => 'lazy',
);
requires '_build_driver';

has 'last_error' => (
    is => 'rw',
    required => 0,
);

has 'last_query' => (
    is => 'rw',
    required => 0,
);

has 'statement' => (
    is => 'rw',
    required => 0,
);

has 'password' => (
    is => 'rw',
    required => 0,
);
has 'username' => (
    is => 'rw',
    required => 0,
);


# disconnect() => 0 | 1
sub disconnect {
    my ($self) = @_;
    eval { $self->statement->finish } if $self->statement;
    return $self->driver ? $self->driver->disconnect : 0;
}

sub dsn {
    my ($self) = @_;
    my $class = ref $self;
    $class =~ s/.*:://;
    return $self->username ?
        sprintf("%s://%s?username=%s", lc($class), $self->database, $self->username) :
        sprintf("%s://%s", lc($class), $self->database);
}

sub execute {
    my ($self, @args) = @_;
    if ($self->statement->execute(@args)) {
        return 1;
    } else {
        $self->last_error($self->statement->errstr);
        return 0;
    }
}

sub fetch_array {
    my ($self) = @_;
    return unless $self->statement;
    return wantarray ? $self->statement->fetchrow_array : $self->statement->fetchrow_arrayref;
}

sub fetch_hash {
    my ($self) = @_;
    return unless $self->statement;
    return wantarray ? %{ $self->statement->fetchrow_hashref } : $self->statement->fetchrow_hashref;
}

sub field_prototypes {
    my ($self) = @_;
    return unless $self->statement;
    return unless $self->is_select;

    my $sth = $self->statement;
    my $names = $sth->{'NAME_lc'};
    my $types = $sth->{'TYPE'};
    my $precs = $sth->{'PRECISION'};

    my $prototypes = [];
    for my $i (0..$#$names) {
        push @$prototypes, {
            name => $names->[$i],
            type => $types->[$i],
            size => $precs->[$i],
        };
    }

    return $prototypes;
}

sub has_result_set {
    return $_[0]->is_select;
}

sub is_select {
    my ($self) = @_;
    return unless $self->statement;
    return defined $self->statement->{'NUM_OF_FIELDS'}
            && $self->statement->{'NUM_OF_FIELDS'} > 0;
}

sub name_completion {
    return ();
}

sub prepare {
    my ($self, $query) = @_;
    $self->last_query($query) if $query;

    unless ($self->last_query) {
        $self->controller->output->error('Execution buffer is empty. Please specify a query or PL/SQL block to execute');
        return 0;
    }

    if ($self->controller->config->echo) {
        $self->controller->output->infof("Query: %s", $self->last_query);
    }

    my $sth = $self->driver->prepare($self->last_query);
    if ($sth) {
        $self->statement($sth);
        return 1;
    } else {
        $self->last_error($sth->errstr);
        $self->statement(undef);
        return 0;
    }
}

# query_is_complete($self, $query) => 0 | 1
sub query_is_complete {
    return 1;
}

# rows_affected() => undef | Int
sub rows_affected {
    my ($self) = @_;
    return $self->statement ? $self->statement->rows : undef;
}

# sanitize($self, $query) => $sanitized_query
sub sanitize {
    return $_[1];
}


1;
