package Rent::PIQT::DB;

use Moo;

with 'Rent::PIQT::Component';

has driver => (is => 'rw');


# connect_string() => $string
sub connect_string {
    return $_[0]->config->connect_string;
}

# disconnect() => 0 | 1
sub disconnect {
    return $_[0]->driver ? $_[0]->driver->disconnect : 0;
}

sub name_completion {
    return ();
}

# query_is_complete($self, $query) => 0 | 1
sub query_is_complete {
    return 1;
}

# sanitize($self, $query) => $sanitized_query
sub sanitize {
    return $_[1];
}


1;
