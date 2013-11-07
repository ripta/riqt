package Rent::PIQT::DB;

use Time::Piece;

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

sub POSTBUILD {
    my ($self) = @_;

    $self->controller->register('load',
        sub {
            my ($ctrl, @rest) = @_;
            die "Syntax error: command takes no arguments" if @rest;
            $ctrl->output->info("Caching object names for tab completion...");

            $ctrl->output->start_timing;
            if (my $objects = $self->object_names) {
                my $ts = localtime();
                $ctrl->cache->set('object_names',       $objects);
                $ctrl->cache->set('object_ts_epoch',    $ts->epoch);
                $ctrl->cache->set('object_ts_iso8601',  $ts->datetime);
                $ctrl->output->okf("Loaded %d objects into cache", scalar(@{ $ctrl->cache->get('object_names') }));
                $ctrl->output->finish_timing;
            } else {
                $ctrl->output->errorf("Could not load objects: %s",
                    $self->last_error || 'unknown error',
                );
                $ctrl->output->reset_timing;
            }

            return 1;
        },
    );
}

sub cleanup_query {
    my ($self, $success) = @_;
    return $success;
}

sub commit {
    my ($self) = @_;
    return $self->driver->commit ? 1 : 0;
}

sub describe_object {
    my ($self, $name) = @_;
    my $o = $self->controller->output;

    # Doing this directly on the driver, because we need access to the statement
    # handle's attributes
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

        if ($info->{'precision'}) {
            if ($info->{'scale'}) {
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

sub display {
    my ($self, $output, $limit) = @_;
    my $row_num = 0;

    $limit //= 0;
    $limit = 0 if $limit && $limit < 0;
    $output->debugf("Limit set to %s", $limit);

    $output->start($self->field_prototypes);
    while (my $row = $self->fetch_array) {
        $output->record([ @$row ]);
        $row_num++;
        last if $limit && $row_num >= $limit;
    }
    $output->finish;
    $output->warn("There may be more rows") if $limit && $row_num >= $limit;
    return $row_num;
}

sub do {
    my ($self, $sql, @args) = @_;
    return $self->prepare($sql) && $self->execute(@args);
}

sub do_and_display {
    my ($self, $sql, $output, %opts) = @_;
    if ($self->do($sql, exists $opts{'args'} ? @{$opts{'args'}} : ())) {
        return $self->display($output, exists $opts{'limit'} ? $opts{'limit'} : undef);
    } else {
        $output->error($self->last_error);
        return undef;
    }
}

sub dsn {
    my ($self) = @_;
    my $class = ref $self;
    $class =~ s/.*:://;
    return $self->username ?
        sprintf("%s://%s?username=%s", lc($class), $self->database, $self->username) :
        sprintf("%s://%s", lc($class), $self->database);
}

sub auth_info {
    my ($self) = @_;
    return $self->username
            ? sprintf('%s@%s', lc $self->username, lc $self->database)
            : lc $self->database;
}

sub execute {
    my ($self, @args) = @_;
    my $o = $self->controller->output;

    if ($self->statement->execute(@args)) {
        $o->debugf("Statement executed with arguments (%s)", join(", ", @args));
        return 1;
    } else {
        $o->debugf("Statement cannot be executed: %s", $self->statement->errstr);
        $self->last_error($self->statement->errstr);
        return 0;
    }
}

sub fetch_all_arrays {
    my ($self) = @_;
    return unless $self->statement;
    return $self->statement->fetchall_arrayref;
}

sub fetch_all_hashes {
    my ($self) = @_;
    return unless $self->statement;
    return $self->statement->fetchall_hashref;
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
    my $sth = $self->statement;

    return unless $sth;
    return unless $self->is_select;

    my $names = $sth->{'NAME_lc'};
    my $types = $sth->{'TYPE'};
    my $precs = $sth->{'PRECISION'};
    my $scale = $sth->{'SCALE'};

    my $prototypes = [];
    for my $i (0..$#$names) {
        my $type;
        if (my $rtype = $self->driver->type_info($types->[$i])) {
            $type = $rtype->{'LOCAL_TYPE_NAME'} || $rtype->{'TYPE_NAME'} || $types->[$i];
        } else {
            $type = $types->[$i];
        }

        if ($type =~ /char/i) {
            $type = 'str';
        } elsif ($type =~ /date|time/i) {
            $type = 'date';
        } elsif ($type =~ /float|decimal|number/i) {
            if ($scale->[$i]) {
                $type = 'float';
            } else {
                $type = 'int';
            }
        } else {
            $type = 'str';
        }

        push @$prototypes, {
            name => $names->[$i],
            type => $type,
            size => $precs->[$i],
        };
    }

    $self->controller->output->debugf("Field prototypes:");
    foreach my $idx (0..$#$prototypes) {
        $self->controller->output->debugf(" #%d | %-40s | %-15s | %-5s",
            $idx,
            $prototypes->[$idx]->{'name'},
            $prototypes->[$idx]->{'type'},
            $prototypes->[$idx]->{'size'},
        );
    }

    return $prototypes;
}

sub has_result_set {
    return $_[0]->is_select;
}

sub is_select {
    my ($self) = @_;
    my $sth = $self->statement;

    return unless $sth;
    return defined $sth->{'NUM_OF_FIELDS'}
            && $sth->{'NUM_OF_FIELDS'} > 0;
}

sub name_completion {
    my ($self, $text, $line, $char) = @_;
    my $c = $self->controller->cache;
    my $o = $self->controller->output;

    my @words;

    $o->debugf("Tab completion (at line %s, char %s) with input '%s'", $line, $char, $text);
    if ($line =~ /^@/) {
        # $TERM->Attribs->{'completion_suppress_append'} = 1;
        push @words, map { -d $_ ? "$_/" : $_ } glob("$text*");
    } else {
        # $TERM->Attribs->{'completion_suppress_append'} = 0;
        my @candidates = ();
        if ($char == 0) {
            push @candidates,
                    qw( SELECT INSERT UPDATE DELETE CREATE DROP ),
                    qw( BEGIN DECLARE ),
                    qw( ED VI ! @ );
            push @candidates, $self->controller->internal_commands;
        } elsif (my $names = $c->get('object_names')) {
            @candidates = sort map { lc $_->{'name'} } @$names;
        } else {
            $o->warn("Tab completion for objects is not available, because the cache is not loaded yet.");
            $o->warn("The object cache can be primed by running 'load' on your prompt.");
        }

        foreach my $word (@candidates) {
            push @words, $word if $word eq lc $text;
        }

        foreach my $word (@candidates) {
            push @words, $word if $word ne $text && $word =~ m/^\Q$text\E/i;
        }
    }

    if (lc $text eq $text) {
        @words = grep { m/^\Q$text\E/ } map { lc } @words;
    } elsif (uc $text eq $text) {
        @words = grep { m/^\Q$text\E/ } map { uc } @words;
    } else {
        @words = map { s/^\Q$text\E/$text/i; $_ } @words;
    }
    return @words;
}

sub object_names {
    my ($self) = @_;

    my $sth = $self->driver->table_info;
    return unless $sth;

    my $tables = $sth->fetchall_arrayref;
    return unless $tables;

    return [map { {type => $_->[3], schema => $_->[1], name => $_->[2]} } @$tables];
}

sub prepare {
    my ($self, $query, %opts) = @_;
    my $o = $self->controller->output;
    $opts{'save_query'} //= 0;

    unless ($query) {
        $self->controller->output->error('No query to execute.');
        return 0;
    }

    die "Cannot connect to database " . $self->dsn . "" unless $self->driver;

    my $sth = $self->driver->prepare($query);
    if ($sth) {
        $o->debugf("Query prepared as %s", $sth);
        $self->statement($sth);
        $self->last_query($query) if $opts{'save_query'};
        return 1;
    } else {
        $o->debugf("Query could not be prepared: %s", $self->driver->errstr);
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
