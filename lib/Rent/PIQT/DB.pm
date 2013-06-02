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


sub DEMOLISH {
    my ($self) = @_;
    $self->disconnect;
}

sub commit {
    my ($self) = @_;
    return $self->driver->commit ? 1 : 0;
}

sub describe_object {
    my ($self, $name) = @_;
    my $o = $self->controller->output;

    my $s = $self->driver->prepare("SELECT * FROM $name WHERE 1=2");
    unless ($s) {
        $o->errorf("Cannot DESCRIBE %s: %s",
            $name,
            $self->driver->errstr,
        );
        return;
    }

    unless ($s->execute) {
        $o->errorf("Cannot DESCRIBE %s: %s",
            $name,
            $s->errstr,
        );
        return;
    }

    my ($names, $types, $precs, $scale, $nulls);
    eval {
        $names = $s->{'NAME'};
        $types = $s->{'TYPE'};
        $precs = $s->{'PRECISION'};
        $scale = $s->{'SCALE'};
        $nulls = $s->{'NULLABLE'};
    };
    if ($@) {
        $o->error($@);
        return;
    }

    my @infos = ();
    for (my $i = 0; $i < scalar @$names; $i++) {
        my $info = {
            name => $names->[$i],
        };

        my $rtype = ($self->driver->type_info($types->[$i]))[0];
        if ($rtype) {
            # Don't check for $rtype->{'NULLABLE'}, which just indicates whether
            # the type itself supports a NULL value or not
            $info->{'null_id'}      = $nulls->[$i] || 0;
            $info->{'type_id'}      = $rtype->{'DATA_TYPE'};
            $info->{'unsigned_id'}  = $rtype->{'UNSIGNED_ATTRIBUTE'} || 0;
            $info->{'auto_unique'}  = $rtype->{'AUTO_UNIQUE_VALUE'} || 0;
            $info->{'params'}       = $rtype->{'CREATE_PARAMS'};
        } else {
            $info->{'null_id'}      = $nulls->[$i] || 0;
            $info->{'type_id'}      = $types->[$i];
            $info->{'unsigned_id'}  = 0;
            $info->{'auto_unique'}  = 0;
            $info->{'params'}       = undef;
        }

        $info->{'unsigned'} = $info->{'unsigned_id'} ? 'UNSIGNED' : '';

        if ($info->{'null_id'} == 0) {
            $info->{'null'} = 'NOT NULL';
        } elsif ($info->{'null_id'} == 1) {
            $info->{'null'} = 'NULL';
        } else {
            $info->{'null'} = '';
        }

        $info->{'type'} = $rtype->{'LOCAL_TYPE_NAME'} || $rtype->{'TYPE_NAME'} || 'UNKNOWN(' . $info->{'type_id'} . ')';
        if ($info->{'type'} =~ m/unknown|date|long/i) {
            $info->{'precision'} = $rtype->{'COLUMN_SIZE'} || $precs->[$i];
            $info->{'scale'} = $scale->[$i] || undef;
        } elsif ($info->{'type'} =~ m/char/i) {
            $info->{'precision'} = $precs->[$i];
            $info->{'scale'} = $scale->[$i] || undef;
        } else {
            $info->{'precision'} = $precs->[$i];
            $info->{'scale'} = $scale->[$i];
        }

        if (defined($info->{'precision'})) {
            if (defined($info->{'scale'})) {
                $info->{'precision_scale'} = sprintf('(%d, %d)', $info->{'precision'}, $info->{'scale'});
            } else {
                $info->{'precision_scale'} = sprintf('(%d)', $info->{'precision'});
            }
        } else {
            $info->{'precision_scale'} = '';
        }

        push @infos, $info;
    }

    $s->finish();
    return @infos;
}

# disconnect() => 0 | 1
sub disconnect {
    my ($self) = @_;
    eval { $self->statement->finish } if $self->statement;
    return $self->driver ? $self->driver->disconnect : 0;
}

sub dsn {
    my ($self) = @_;
    return $self->username
            ? sprintf('%s@%s', $self->username, $self->database)
            : $self->database;
    # my $class = ref $self;
    # $class =~ s/.*:://;
    # return $self->username ?
    #     sprintf("%s://%s?username=%s", lc($class), $self->database, $self->username) :
    #     sprintf("%s://%s", lc($class), $self->database);
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
        $self->last_error($self->driver->errstr);
        $self->statement(undef);
        return 0;
    }
}

# query_is_complete($self, $query) => 0 | 1
sub query_is_complete {
    return 1;
}

sub rollback {
    my ($self) = @_;
    return $self->driver->rollback ? 1 : 0;
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
