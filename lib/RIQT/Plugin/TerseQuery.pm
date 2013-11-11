package RIQT::Plugin::TerseQuery;

use List::Util qw/max/;
use Moo;
use RIQT::Util;

our $VERSION = '0.5.0';

with 'RIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('`', {
        signature => [
            "%s <relation_set> [<conditions>] [<projections>]",
        ],
        help => qq/
            Execute a Terse Query.

            The <relation_set> is a set of relations, which must be marked with
            parentheses, e.g.:

                ` (phone_numbers_t)

            Multiple relations may be comma-delimited:

                ` (properties_t, phone_numbers_t)

            Relations may be abbreviated, as long as it is not ambiguous:

                ` (prop*, phone*)

            The <conditions> portion is optional, and must be marked with square
            brackets, e.g.:

                ` (phone_numbers_t) [property_id = 12345]

            As with relations, attributes may be abbreviated:

                ` (phone*) [prop* = 12345]

            Joins can be performed on specific attribute, or the attribute left out
            entirely if the join should be performed on all attributes named the same
            by using the cross operator "x":

                ` (phone*, prop*) [property_id]
                ` (phone*, prop*) [prop*]
                ` (phone* x prop*)

            Queries may be nested as a relation in itself:

                ` ((phone*, prop*) [prop*]) [prop* > 12345]

            The <projections> portion is optional, and must be marked with curly braces:

                ` (prop*) {property_id, name}

            Projections may be renamed:

                ` (prop*) {prop* -> pid, name}

            Aggregate functions in the projection automatically cause a summarization:

                ` (properties) {businessmodel_tp}#count

            which is equivalent to:

                SELECT businessmodel_tp, COUNT(*)
                FROM properties GROUP BY businessmodel_tp;

            Joins can be specified as in other terse queries:

                ` (prop* x phone*) [business* IN ('cpa', 'plt')] {business*}#count

            which is equivalent to:

                SELECT businessmodel_tp, COUNT(*)
                FROM properties JOIN phones USING (property_id)
                WHERE businessmodel_tp IN ('cpa', 'plt')
                GROUP BY businessmodel_tp;
        /,
        slurp => 1,
        code => sub {
            my ($ctrl, $args) = @_;
            my $o = $ctrl->output;

            $o->info('TERSE (EXPANSION=1)');

            return 1;
        },
    });
}

1;
