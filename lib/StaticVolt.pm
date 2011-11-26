package StaticVolt;

use strict;
use warnings;

use Cwd qw( getcwd );
use File::Copy qw( copy );
use File::Find;
use File::Path qw( mkpath rmtree );
use File::Spec;
use FindBin;
use Template;
use YAML;

use base qw( StaticVolt::Convertor );

sub new {
    my ( $class, %config ) = @_;

    my %config_defaults = (
        'includes'    => '_includes',
        'layouts'     => '_layouts',
        'source'      => '_source',
        'destination' => '_destination',
    );

    for my $config_key ( keys %config_defaults ) {
        $config{$config_key} = $config{$config_key}
          || $config_defaults{$config_key};
        $config{$config_key} = File::Spec->canonpath( $config{$config_key} );
    }

    return bless \%config, $class;
}

sub _clean_destination {
    my $self = shift;

    my $destination = $self->{'destination'};
    rmtree $destination;

    return;
}

sub _traverse_files {
    my $self = shift;

    push @{ $self->{'files'} }, $File::Find::name;

    return;
}

sub _gather_files {
    my $self = shift;

    my $source = $self->{'source'};
    find sub { _traverse_files $self }, $source;

    return;
}

sub _extract_file_config {
    my ( $self, $fh_source_file ) = @_;

    my $delimiter = qr/^---\n$/;
    if ( <$fh_source_file> =~ $delimiter ) {
        my @yaml_lines;
        while ( my $line = <$fh_source_file> ) {
            if ( $line =~ $delimiter ) {
                last;
            }
            push @yaml_lines, $line;
        }

        return Load join '', @yaml_lines;
    }
}

sub compile {
    my $self = shift;

    $self->_clean_destination;
    $self->_gather_files;

    my $source      = $self->{'source'};
    my $destination = $self->{'destination'};
    for my $source_file ( @{ $self->{'files'} } ) {
        my $destination_file = $source_file;
        $destination_file =~ s/^$source/$destination/;
        if ( -d $source_file ) {
            mkpath $destination_file;
            next;
        }

        open my $fh_source_file, '<', $source_file
          or die "Failed to open $source_file for input: $!";
        my $file_config = $self->_extract_file_config($fh_source_file);

        # For files that do not have a configuration defined, copy them over
        unless ($file_config) {
            copy $source_file, $destination_file;
            next;
        }

        my ($extension) = $source_file =~ m/\.(.+?)$/;

        # If file does not have a registered convertor and is not an HTML file,
        # copy the file over to the destination and skip current loop iteration
        if ( !$self->has_convertor($extension) && $extension ne 'html' ) {
            copy $source_file, $destination_file;
            next;
        }

        # Only files that have a registered convertor need to be handled

        $destination_file =~ s/\..+?$/.html/;    # Change extension to .html

        my $file_layout      = $file_config->{'layout'};
        my $includes         = $self->{'includes'};
        my $layouts          = $self->{'layouts'};
        my $abs_include_path = File::Spec->catfile( getcwd, $includes );
        my $abs_layout_path =
          File::Spec->catfile( getcwd, $layouts, $file_layout );
        my $template = Template->new(
            'INCLUDE_PATH' => $abs_include_path,
            'WRAPPER'      => $abs_layout_path,
            'ABSOLUTE'     => 1,
        );

        my $source_file_content = do { local $/; <$fh_source_file> };
        my $converted_content;
        if ( $extension eq 'html' ) {
            $converted_content = $source_file_content;
        }
        else {
            $converted_content =
              $self->convert( $source_file_content, $extension );
        }

        open my $fh_destination_file, '>', $destination_file
          or die "Failed to open $destination_file for output: $!";
        if ($file_layout) {
            $template->process( \$converted_content, $file_config,
                $fh_destination_file )
              or die $template->error;
        }
        else {
            print $fh_destination_file $converted_content;
        }

        close $fh_source_file;
        close $fh_destination_file;
    }
}

1;
