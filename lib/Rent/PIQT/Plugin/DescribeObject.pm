package Rent::PIQT::Plugin::DescribeObject;

use List::Util qw/max/;
use Moo;
use Rent::PIQT::Util;

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('desc', 'describe', {
        signature => [
            '%s <object_name>',
            '%s <object_name> LIKE <criterion>',
            '%s <object_name> =~ <regexp>',
        ],
        help => q{
            Describe any object that can be SELECT from.

            The <object_name> can be quoted (single- or double-) or left verbatim. When
            quoted, behavior depends on the behavior of quoted objects in your driver:

                DESCRIBE new_table
                DESCRIBE 'new_table'
                DESCRIBE "new_table"

            If a LIKE clause is specified, see 'HELP :LIKE'. If a =~ clause is specified,
            see 'HELP :REGEXP'.
        },
        code => sub {
            my ($ctrl, $object_name, $mode, $col_spec, @rest) = @_;
            my $o = $ctrl->output;

            if (!$mode) {
                $mode = '';
            } elsif ($mode =~ /^like$/i) {
                $mode = 'like';
            } elsif ($mode =~ /^=~$/) {
                $mode = 'regexp';
            } else {
                $o->errorf("Syntax error: unexpected %s; expected LIKE or =~", quote($mode));
                return 1;
            }

            my @infos = $ctrl->db->describe_object($object_name);
            return 1 unless @infos;

            my @shown = @infos;
            if ($mode) {
                my $regexp = $mode eq 'like' ? like_to_regexp $col_spec : rstring_to_regexp $col_spec;
                @shown = grep { $_->{'name'} =~ $regexp } @shown;
            }

            $o->data_set(
                [
                    {name => 'Column Name', type => 'str', length => max(11, map { length $_->{'name'} } @infos)},
                    {name => 'Type',        type => 'str', length => max( 4, map { length $_->{'type'} . $_->{'precision_scale'} } @infos)},
                    {name => 'Nullable',    type => 'str', length => max( 8, map { length $_->{'null'} } @infos)},
                ],
                map { [ @{$_}{qw/name type null/} ] } @shown,
            );

            $o->okf(
                "Displayed %s out of %s",
                scalar(@shown),
                pluralize(scalar(@infos), 'column', 'columns'),
            );

            return 1;
        },
    });
}

1;
