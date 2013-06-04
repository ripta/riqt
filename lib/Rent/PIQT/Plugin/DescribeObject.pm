package Rent::PIQT::Plugin::DescribeObject;

use List::Util qw/max/;
use Moo;

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('desc', 'describe',
        sub {
            my ($ctrl, $object_name) = @_;
            my @infos = $ctrl->db->describe_object($object_name);
            $ctrl->output->data_set(
                [
                    {name => 'Column Name', type => 'str', length => max(11, map { length $_->{'name'} } @infos)},
                    {name => 'Type',        type => 'str', length => max( 4, map { length $_->{'type'} . $_->{'precision_scale'} } @infos)},
                    {name => 'Nullable',    type => 'str', length => max( 8, map { length $_->{'null'} } @infos)},
                ],
                map { [ @{$_}{qw/name type null/} ] } @infos,
            );
            return 1;
        },
    );
}

1;
