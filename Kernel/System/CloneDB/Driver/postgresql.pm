# --
# Kernel/System/CloneDB/Driver/postgresql.pm - Delegate for CloneDB postgresql Driver
# Copyright (C) 2001-2014 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::CloneDB::Driver::postgresql;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(Kernel::System::CloneDB::Driver::Base);

=head1 NAME

Kernel::System::CloneDB::Driver::postgresql

=head1 SYNOPSIS

CloneDBs postgresql Driver delegate

=head1 PUBLIC INTERFACE

This module implements the public interface of L<Kernel::System::CloneDB::Backend>.
Please look there for a detailed reference of the functions.

=over 4

=item new()

usually, you want to create an instance of this
by using Kernel::System::CloneDB::Backend->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed objects
    for my $Needed (
        qw(ConfigObject EncodeObject LogObject MainObject SourceDBObject BlobColumns CheckEncodingColumns)
        )
    {
        die "Got no $Needed!" if !$Param{$Needed};

        $Self->{$Needed} = $Param{$Needed};
    }

    return $Self;
}

#
# create external db connection.
#
sub CreateTargetDBConnection {
    my ( $Self, %Param ) = @_;

    # check TargetDBSettings
    for my $Needed (
        qw(TargetDatabaseHost TargetDatabase TargetDatabaseUser TargetDatabasePw TargetDatabaseType)
        )
    {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $Needed for external DB settings!"
            );
            return;
        }
    }

    # include DSN for target DB
    $Param{TargetDatabaseDSN} =
        "DBI:Pg:dbname=$Param{TargetDatabase};host=$Param{TargetDatabaseHost};";

    # create target DB object
    my $TargetDBObject = Kernel::System::DB->new(
        %{$Self},
        DatabaseDSN  => $Param{TargetDatabaseDSN},
        DatabaseUser => $Param{TargetDatabaseUser},
        DatabasePw   => $Param{TargetDatabasePw},
        Type         => $Param{TargetDatabaseType},
    );

    if ( !$TargetDBObject ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Could not connect to target DB!"
        );
        return;
    }

    return $TargetDBObject;
}

#
# List all tables in the source database in alphabetical order.
#
sub TablesList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(DBObject)) {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Needed!" );
            return;
        }
    }

    $Param{DBObject}->Prepare(
        SQL => "
            SELECT table_name
            FROM information_schema.tables
            WHERE table_name !~ '^pg_+'
                AND table_schema != 'information_schema'
            ORDER BY table_name ASC"
    ) || die @!;

    my @Result;
    while ( my @Row = $Param{DBObject}->FetchrowArray() ) {
        push @Result, $Row[0];
    }
    return @Result;
}

#
# List all columns of a table in the order of their position.
#
sub ColumnsList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(DBObject Table)) {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Needed!" );
            return;
        }
    }

    $Param{DBObject}->Prepare(
        SQL => "
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name = ?
            ORDER BY ordinal_position ASC",
        Bind => [
            \$Param{Table},
        ],
    ) || die @!;

    my @Result;
    while ( my @Row = $Param{DBObject}->FetchrowArray() ) {
        push @Result, $Row[0];
    }
    return @Result;
}

#
# Reset the 'id' auto-increment field to the last one in the table.
#
sub ResetAutoIncrementField {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(DBObject Table)) {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $Needed!" );
            return;
        }
    }

    $Param{DBObject}->Prepare(
        SQL => "
            SELECT id
            FROM $Param{Table}
            ORDER BY id DESC",
        Limit => 1,
    ) || die @!;

    my $LastID;
    while ( my @Row = $Param{DBObject}->FetchrowArray() ) {
        $LastID = $Row[0];
    }

    # add one more to the last ID
    $LastID++;

    my $SQL = "
        ALTER SEQUENCE IF EXISTS $Param{Table}_id_seq RESTART WITH $LastID;
    ";

    $Param{DBObject}->Do(
        SQL => $SQL,
    ) || die @!;

    return 1;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
