# ABSTRACT: Static website_ generator

package StaticVolt
{
  $StaticVolt::VERSION = '1.00';
}

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

use Data::Dumper;

use base qw( PLog::Generator::Convertor );

use PLog::Generator::Convertor::Textile;

sub new {
    my ( $class, %config ) = @_;
	
    my %config_defaults = (
        'includes'    => '_includes',
        'layouts'     => '_layouts',
	'blog_source' => '_blog_source',        
	'source'      => '_source',
        'destination' => '_site',
        'blog_destination' => '_site/blog',
    );

    for my $config_key ( keys %config_defaults ) {
        $config{$config_key} = $config{$config_key}
          || $config_defaults{$config_key};
        $config{$config_key} = File::Spec->canonpath( $config{$config_key} );
    }

	my $siteconfig = \%config;
	
	bless $siteconfig, $class;
	$siteconfig->initialize;
	
    return $siteconfig;
}

# gather all posts, pages, staticfiles and directories
sub initialize {
	my ($self) = @_;
	
	# First gather all posts and the settings of the post
	$self->_gather_files;
	
}

# Säubere das Zielverzeichnis
sub _clean_destination {
    my $self = shift;

    my $destination = $self->{'destination'};
    rmtree $destination;

    return;
}

# Durchlauf die Dateien
sub _traverse_files {
    my $self = shift;
    
    my $source_file = $File::Find::name;
    my $source = $self->{'source'};
    my $blog_source = $self->{'blog_source'};
    
   # If the file is a directory, push it to the directory array
   if ( -d $source_file ) {
        push @{ $self->{'directories'} }, $source_file;
   }
    
   # Relevant source files are text files and have the extension 
   # .textile
   # TODO: Add more extension for markdown etc.
   elsif (-T $source_file and $source_file =~ m/.textile$/) {
	
	open my $fh_source_file, '<:encoding(utf8)', $source_file
        or die "Failed to open $source_file for input: $!";
   	my ($file_config, undef) = $self->_extract_file_config($fh_source_file);
   	my $type = $file_config->{'type'} || '';

   	# For files that do not have a configuration defined, copy them over as static files
   	unless ( $file_config) {
        	push @{ $self->{'staticfiles'} }, $source_file;
        }
        else {
        	my ($extension) = $source_file =~ m/\.(.+?)$/;

        	# If file does not have a registered convertor and is not an HTML
        	# file, copy the file over to the destination and skip current loop iteration
        	if ( !$self->has_convertor($extension) && $extension ne 'html' ) {
            	push @{ $self->{'staticfiles'} }, $source_file;
        	}
        	# Check whether th source file is a blog source
        	# this is the case, if it has the correct format! 
        	# Blog sources have always the follwing format:
        	# YYYYMMDD_title.$extension
        	elsif ($source_file =~ m/\d{6}_.*\.$extension$/ and $source_file =~ m/$blog_source/) {
       			
        		# Almost all relevant datas for the post are saved in the
    			# yaml lines we extraced already above
    			$file_config->{'filename'} = $source_file;
    			
    			# For sorting we need a date_raw key
    			# If the user saved a date in the yaml config, take this
    			# so that we can sort by date and time!!!
    			my $date = $file_config->{'date'};
    			if ($date) {
    				chomp $date;
    				# The date has to be saved as follow:
    				# YYYY-MM-DD HH:MM:SS
    				# we delete all non digits and get: YYYYMMDDHHMMSS
    				$date =~ s/\D+//g;
    				$file_config->{'date_raw'} = $date
    			}
    			else {
    				my (undef,undef, $filename) = File::Spec->splitpath($source_file);
        			# the first 6 digit contains the date in the form YYYYMMDD
					$filename =~ /(\d{8})_(.*)(\.$extension)$/;
					my $date_raw = $1;
					$file_config->{'date_raw'} = $date_raw;
				}
	
    			# After that we only need the teaser part
    			# The record seperator is \n---
    			local $/="\n---";
    			if (<$fh_source_file>) {
    				my $teaser = <$fh_source_file>;
    				chomp $teaser;
					$file_config->{'teaser'} = $self->convert( $teaser, "$extension" );
    			}
    			
    			# Push the post hash reference ($file_config) to the array ref
    			# $self->{'posts'}
    			push @{ $self->{'posts'} }, $file_config;
    			
    			# Sort the posts
    			@{ $self->{'posts'} } = sort {
				if ($a->{'date_raw'} lt $b->{'date_raw'}) {return 1}
				elsif ($a->{'date_raw'} gt $b->{'date_raw'}) {return -1}
				else {return 0}
				} @{ $self->{'posts'} };
			}
        	
        	# If file is a bloglist, we handle it as a static page 
        	elsif ($type eq 'bloglist') {
        		# Almost all relevant datas for the post are saved in the
    			# yaml lines we extraced already above
    			$file_config->{'filename'} = $source_file;
    			
    			my (undef,$pagedirectory,$pagefile) = File::Spec->splitpath($source_file);
				
				my $url = '';
				$url = File::Spec->abs2rel($pagedirectory, $source) if ($pagedirectory =~ m/$source/);
				$url = File::Spec->abs2rel($pagedirectory, $blog_source) if ($pagedirectory =~ m/$blog_source/);
				
				# the root site shall be shown as "/" or "/blog/" if it is located in the blog dir
				$url = "/$url" if ($pagedirectory =~ m/$source/);
				$url = "/blog/$url" if ($pagedirectory =~ m/$blog_source/);
	
				$file_config->{'url'} = "$url";
				$file_config->{'pagedirectory'} = "$pagedirectory";
				$file_config->{'pagefile'} = "$source_file";
	
				# this could be important in latter versions!
				# At the moment no importance!
				$file_config->{'articles'} = undef;
	
				$file_config->{'subpage'} = 0;
    			
    			# Push the post hash reference ($file_config) to the array ref
        		
        		push @{ $self->{'blogindexfiles'} }, $file_config;

        	}
        	
        	# Everything else is a normal static page
        	else {
        		
        		# Almost all relevant datas for the post are saved in the
    			# yaml lines we extraced already above
    			$file_config->{'filename'} = $source_file;
    			
    			my (undef,$pagedirectory,$pagefile) = File::Spec->splitpath($source_file);
				
				my $url = '';
				$url = File::Spec->abs2rel($pagedirectory, $source) if ($pagedirectory =~ m/$source/);
				$url = File::Spec->abs2rel($pagedirectory, $blog_source) if ($pagedirectory =~ m/$blog_source/);
				
				# the root site shall be shown as "/" or "/blog/" if it is located in the blog dir
				$url = "/$url" if ($pagedirectory =~ m/$source/);
				$url = "/blog/$url" if ($pagedirectory =~ m/$blog_source/);
	
				$file_config->{'url'} = "$url";
				$file_config->{'pagedirectory'} = "$pagedirectory";
				$file_config->{'pagefile'} = "$source_file";
	
				# this could be important in latter versions!
				# At the moment no importance!
				$file_config->{'articles'} = undef;
	
				$file_config->{'subpage'} = 0;
    			
    			# Push the post hash reference ($file_config) to the array ref
    			# $self->{'posts'}
    			push @{ $self->{'pages'} }, $file_config;
        		
        	}
    	}
    	close $fh_source_file;
    }
    
    # If the source file is no text file or has not the right extension, then it is a static file
    else {
    	push @{ $self->{'staticfiles'} }, $source_file;
    }

    return;
}

# Sammle die Dateien
sub _gather_files {
    my $self = shift;

    my $source = $self->{'source'};
    my $blog_source = $self->{'blog_source'};
    
    find sub { _traverse_files($self) }, $source;
    find sub { _traverse_files($self) }, $blog_source;

    return;
}

sub _extract_file_config {
    my ( $self, $fh_source_file ) = @_;

	local $/;
	my $content = <$fh_source_file>;
    
	my (undef, $yaml_lines, $content_raw) = split "---\n", $content, 3;
	
	my $file_config = Load $yaml_lines;
		
	return ($file_config, $content_raw);
}

sub compile {
    my $self = shift;

    $self->_clean_destination;
    
    # 1) CREATE THE DIRECTORIES
    foreach my $directory_file (@{ $self->{'directories'} }) {
    
    	my $destination_file = $self->_get_destination_path($directory_file);
    	
    	mkpath $destination_file or warn "Could not create $destination_file: $!\n";
    }
    
    # 2) Copy the static files over
    foreach my $staticfile (@{ $self->{'staticfiles'} } ) {
    	my $destination_file = $self->_get_destination_path($staticfile);
    	my ($readtime, $writetime) = (stat($staticfile))[8,9];
        copy ($staticfile, $destination_file) or warn "Could not copy $destination_file: $!\n";
        utime ($readtime, $writetime, $destination_file);
    }
    
    # 3) Convert the content of the pages/source_files
    foreach my $page ( @{ $self->{'pages'} } ) {
        my $source_file = $page->{'filename'};
        my $destination_file = $self->_get_destination_path($source_file);
        
        print "SOURCE $source_file\n";
        open my $fh_source_file, '<:encoding(utf8)', $source_file
          or die "Failed to open $source_file for input: $!";
        my ($file_config, $source_file_content) = $self->_extract_file_config($fh_source_file);

        $destination_file =~ s/\..+?$/.html/;    # Change extension to .html
		
        my $file_layout      = $file_config->{'layout'};
        my $includes         = $self->{'includes'};
        my $layouts          = $self->{'layouts'};
        
        # BUGFIX 1
        # If you create the StaticVolt with different absolute layout, includes etc. directories
        # and therefore start $stratovolt->compile from a different cwd than the directory
        # which contains _includes, _layouts etc, don't use getcwd
        my $abs_include_path;
        my $abs_layout_path;
        
       	if (File::Spec->file_name_is_absolute( $includes ) ) {
        	$abs_include_path = File::Spec->catfile( $includes );
        }
        else {
        	$abs_include_path = File::Spec->catfile( getcwd, $includes );
        }
        if (File::Spec->file_name_is_absolute( $layouts ) ) {
        	$abs_layout_path = File::Spec->catfile( $layouts, $file_layout );
        }
        else {
        	$abs_layout_path = File::Spec->catfile( getcwd, $layouts, $file_layout );
        }
        
        my $template = Template->new(
            'INCLUDE_PATH' => $abs_include_path,
            'WRAPPER'      => $abs_layout_path,
	    'TAG_STYLE'	=> 'asp',
	    'ENCODING' => 'UTF-8',
            'ABSOLUTE'     => 1,
        );
		
	# RELBASE BUGFIX: Add the rel base to the links
	my $sv_rel_base = $self->_relative_path ( $destination_file );
	$source_file_content =~ s/\<\%\s*sv_rel_base\s*\%\>/$sv_rel_base/g;
	
        my $converted_content;
        
        my ($extension) = $source_file =~ m/\.(.+?)$/;
        
        if ( $extension eq 'html' ) {
            $converted_content = $source_file_content;
        }
        else {
            $converted_content =
              $self->convert( $source_file_content, $extension );
        }

        $self->{sv_rel_base} = $self->_relative_path ( $destination_file );

        open my $fh_destination_file, '>:encoding(utf8)', $destination_file
          or die "Failed to open $destination_file for output: $!";
        if ($file_layout) {
        	$self->{'page'} = $file_config;
        	$self->{'post'} = '';
            $template->process( \$converted_content, $self,
                $fh_destination_file )
              or die $template->error;
        }
        else {
            print $fh_destination_file $converted_content;
        }

        close $fh_source_file;
        close $fh_destination_file;
    }
    
    # 4) Convert the content of the blog posts
    foreach my $post_ref ( @{ $self->{'posts'} } ) {
        my $source_file = $post_ref->{'filename'};
        
        my $destination_file = $self->_get_destination_path($source_file);
        
        # second step: Change the extension of the destination_file to .html
        $destination_file =~ s/\..+?$/.html/;

		# But we want the following format /home/user/_site/2016/01/31/title/index.html
		my (undef, $directories, $filename) = File::Spec->splitpath($destination_file);
		$filename =~ /(\d{4})(\d{2})(\d{2})_(.*)(\.html)$/ ;
		my $year = $1;
		my $month = $2;
		my $day = $3;
		my $title_url = $4;
		my $ext = $5;
		
		my $blog_destination = $self->{'blog_destination'};
		$destination_file = "$blog_destination/$year/$month/$day/$title_url/index.html";
		
		# create the directory if it doesn't exist
		mkpath "$blog_destination/$year/$month/$day/$title_url" if (! -e "$blog_destination/$year/$month/$day/$title_url");
		
        my $file_layout      = $post_ref->{'layout'};
        my $includes         = $self->{'includes'};
        my $layouts          = $self->{'layouts'};
        
        # BUGFIX 1
        # If you create the StaticVolt with different absolute layout, includes etc. directories
        # and therefore start $stratovolt->compile from a different cwd than the directory
        # which contains _includes, _layouts etc, don't use getcwd
        my $abs_include_path;
        my $abs_layout_path;
        
       	if (File::Spec->file_name_is_absolute( $includes ) ) {
        	$abs_include_path = File::Spec->catfile( $includes );
        }
        else {
        	$abs_include_path = File::Spec->catfile( getcwd, $includes );
        }
        if (File::Spec->file_name_is_absolute( $layouts ) ) {
        	$abs_layout_path =
          File::Spec->catfile( $layouts, $file_layout );
        }
        else {
        	$abs_layout_path =
          File::Spec->catfile( getcwd, $layouts, $file_layout );
        }
        my $template = Template->new(
            'INCLUDE_PATH' => $abs_include_path,
            'WRAPPER'      => $abs_layout_path,
	    'TAG_STYLE'	=> 'asp',
	    'ENCODING' => 'UTF-8',
            'ABSOLUTE'     => 1,
        );

        # Now excerpt the content of the post
        open my $fh, "<", $post_ref->{'filename'};
        my (undef, $source_file_content) = $self->_extract_file_config($fh);
        close $fh;
        
        # RELBASE BUGFIX: Add the rel base to the links
	my $sv_rel_base = $self->_relative_path ( $destination_file );
	$source_file_content =~ s/\<\%\s*sv_rel_base\s*\%\>/$sv_rel_base/g;
        
        my ($extension) = $source_file =~ m/\.(.+?)$/;
	my $converted_content = '';
        if ( $extension eq 'html' ) {
            $converted_content = $source_file_content;
        }
        else {
            $converted_content =
              $self->convert( $source_file_content, $extension );
        }

        $post_ref->{sv_rel_base} = $self->_relative_path ( $destination_file );

        open my $fh_destination_file, '>:encoding(utf8)', $destination_file
          or die "Failed to open $destination_file for output: $!";
        if ($file_layout) {
        	$self->{'page'} = '';
        	$self->{'post'} = $post_ref;
            $template->process( \$converted_content, $self,
                $fh_destination_file )
              or die $template->error;
        }
        else {
            print $fh_destination_file $converted_content;
        }

        close $fh_destination_file;
    }
    
    # 5) Create a Blog List
    for my $bloglist_object ( @{ $self->{'blogindexfiles'} } ) {
        my $bloglist_file = $bloglist_object->{'filename'};
        my $destination_file = $self->_get_destination_path($bloglist_file);
        
        open my $fh_bloglist_file, '<:encoding(utf8)', $bloglist_file
          or die "Failed to open $bloglist_file for input: $!";
        my ($file_config, $source_file_content) = $self->_extract_file_config($fh_bloglist_file);
        
        
        $destination_file =~ s/\..+?$/.html/;    # Change extension to .html

		my $file_layout      = $file_config->{'layout'};
		my $includes         = $self->{'includes'};
		my $layouts          = $self->{'layouts'};
		    
		# BUGFIX 1
		# If you create the StaticVolt with different absolute layout, includes etc. directories
		# and therefore start $stratovolt->compile from a different cwd than the directory
		# which contains _includes,_layouts etc, don't use getcwd
		my $abs_include_path;
		my $abs_layout_path;
		    
		if (File::Spec->file_name_is_absolute( $includes ) ) {
		  	$abs_include_path = File::Spec->catfile( $includes );
		}
		else {
		   	$abs_include_path = File::Spec->catfile( getcwd, $includes );
		}
		if (File::Spec->file_name_is_absolute( $layouts ) ) {
		   	$abs_layout_path = File::Spec->catfile( $layouts, $file_layout );
		}
		else {
		   	$abs_layout_path = File::Spec->catfile( getcwd, $layouts, $file_layout );
		}
		
		my $template = Template->new(
	        'INCLUDE_PATH' => $abs_include_path,
	        'WRAPPER'      => $abs_layout_path,
		'TAG_STYLE'	=> 'asp',
		'ENCODING'	=> 'UTF-8',
	        'ABSOLUTE'     => 1,
	    );
	    
	    # RELBASE BUGFIX: Add the rel base to the links
	    my $sv_rel_base = $self->_relative_path ( $destination_file );
	    $source_file_content =~ s/\<\%\s*sv_rel_base\s*\%\>/$sv_rel_base/g;
	    
	    my $converted_content;
	    
	    my ($extension) = $bloglist_file =~ m/\.(.+?)$/;
	    
	    if ( $extension eq 'html' ) {
	        $converted_content = $source_file_content;
	    }
	    else {
	        $converted_content =
	          $self->convert( $source_file_content, $extension );
	    }
		    
        # If pagination is set, we must make more pages and give a paginator object
        # with special content
        if ($file_config->{'pagination'} ) {
        	my $per_page = $file_config->{'pagination'};
        	my $paginator_category = $file_config->{'category'};
        	
        	my @paginator_total_posts;
        	if ($paginator_category) {
        		my $key = "posts_" . $paginator_category;
			@paginator_total_posts = @{ $self->{"$key"} };
        	}
        	else {
        		@paginator_total_posts = @{ $self->{'posts'} };
        	}
        	my $total_posts = @paginator_total_posts;
        	my $total_pages = $total_posts / $per_page;
        	my $per_page_last_page = $total_posts % $per_page;
        	
        	if ($per_page_last_page) {
        		$total_pages = int($total_pages);
        		$total_pages = $total_pages + 1;
        	}
        	else {
        		$per_page_last_page = $per_page;
        	}
        	
        	# Add the inforamtions to the siteobject
        	my @paginator_posts = ();
        	my $first_page_link;
        	my $next_page_link;
        	my $previous_page_link;
        	my %paginator_hash = (	'per_page' => $per_page,
        							'total_posts' => $total_posts,
        							'total_pages' => $total_pages,
        							'posts' => \@paginator_posts
        							);
        							
        	$self->{'paginator'} = \%paginator_hash;
        	$self->{'page'} = $file_config;
        	$self->{'post'} = '';
        	
        	############
        	# THE FIRST PAGE can be reached without a page addition
        	# for example: www.example.de/tag/index.html
        	for (my $i = 1; $i<= $per_page; $i++) {
        		my $firstelement = shift @paginator_total_posts;
        		push @paginator_posts, $firstelement;
        	}
        	
        	# The Paginator Links objects and the rel Path Variable for use with TT
        	my $relpath = $self->_relative_path ( $destination_file );
        	$self->{sv_rel_base} = $relpath;
        	$self->{'paginator'}->{'next_page_link'} = "./page2";
        	
        	open my $fh_destination_file, '>:encoding(utf8)', $destination_file
		      or die "Failed to open $destination_file for output: $!";
		    
		    if ($file_layout) {
		        $template->process( \$converted_content, $self,
		            $fh_destination_file )
		          or die $template->error;
		    }
		    else {
		        print $fh_destination_file $converted_content;
		    }

		    close $fh_destination_file;
		    
		    
		    #########
		    # THE OTHER PAGES
		    for (my $i = 2; $i <= $total_pages; $i++) {
		    	
		    	undef @paginator_posts;
				
				for (my $i = 1; $i<= $per_page; $i++) {
		    		# TO DO: Proof, whether @paginator_total_posts contain elements 
		    		my $firstelement = shift @paginator_total_posts;
		    		push @paginator_posts, $firstelement;
		    	}
		    	
		    	my ($dummy1,$destination_dir,$destination_filename) = File::Spec->splitpath( $destination_file );
		    	my $page_destination_file = "$destination_dir/page"."$i"."/$destination_filename";
		    	mkpath "$destination_dir/page$i";
		    	
		    	# The Paginator Links objects and the rel Path Variable for use with TT
		    	my $relpath = $self->_relative_path ( $page_destination_file );
        		$self->{sv_rel_base} = $relpath;
        		$self->{'paginator'}->{'first_page_link'} = "../";
        		if ( $i == $total_pages) {
        			undef $self->{'paginator'}->{'next_page_link'};
        		}
        		else {
        			$self->{'paginator'}->{'next_page_link'} = "../page".($i+1) unless ($i == $total_pages);
        		}
        		
        		if ($i == 2) { $self->{'paginator'}->{'previous_page_link'} = "../" if ($i == 2);}
        		else { $self->{'paginator'}->{'previous_page_link'} = "../page".($i-1)}
        		
		    	
		    	open my $fh_destination_file, '>:encoding(utf8)', $page_destination_file
				  or die "Failed to open $page_destination_file for output: $!";
				
				if ($file_layout) {
				    $template->process( \$converted_content, $self,
				        $fh_destination_file )
				      or die $template->error;
				}
				else {
				    print $fh_destination_file $converted_content;
				}

				close $fh_destination_file;
		    }
		    
        }
        # If pagination is not set, all posts go on one page
        # In result this is the same as generating a normal static page
        else {

		    open my $fh_destination_file, '>:encoding(utf8)', $destination_file
		      or die "Failed to open $destination_file for output: $!";
		    if ($file_layout) {
		        $template->process( \$converted_content, $self,
		            $fh_destination_file )
		          or die $template->error;
		    }
		    else {
		        print $fh_destination_file $converted_content;
		    }

		    close $fh_destination_file;
		}
	 close $fh_bloglist_file;
    }
}

sub _get_destination_path {
	
	my ($self, $source_file) = @_;
	
	# $source is e.g. /home/user/_source or /home/user/_blog_source
    my $blog_source = $self->{'blog_source'};
    my $source      = $self->{'source'};
    
    # $destination is e.g. /home/user/_site or /home/user/_site/blog
    my $destination = $self->{'destination'};
    my $blog_destination = $self->{'blog_destination'};
    
	my $destination_file = $source_file;
        if ($destination_file =~ m/$source/) {
        	$destination_file =~ s/^$source/$destination/;
    	}
    	if ($destination_file =~ m/$blog_source/) {
    		$destination_file =~ s/^$blog_source/$blog_destination/;
    	} 
    	#else {
    	#	$destination_file = '';
    	#}
    	
    return $destination_file;

}

sub _relative_path {

    my ($self,$dest_file) = @_;

    my ($dummy1,$dest_file_dir,$dummy2) = File::Spec->splitpath( $dest_file );

    my $rel_path = File::Spec->abs2rel ( $self->{'destination'},
                                         $dest_file_dir );

    $rel_path .= "/" if $rel_path;

    return $rel_path;

};

1;

__END__

=pod

=head1 NAME

StaticVolt - Static website generator

=head1 VERSION

version 1.00

=head1 SYNOPSIS

    use StaticVolt;

    my $staticvolt = StaticVolt->new;  # Default configuration
    $staticvolt->compile;

=over

=item C<new>

Accepts an optional hash with the following parameters:

    # Override configuration (parameters set explicitly)
    my $staticvolt = StaticVolt->new(
        'includes'    => '_includes',
        'layouts'     => '_layouts',
        'source'      => '_source',
        'blog_source' => '_blog_source',
        'destination' => '_site',
        'blog_destination' => '_site/blog',
    );

=over 4

=item * C<includes>

Specifies the directory in which to search for template files. By default, it
is set to C<_includes>.

=item * C<layouts>

Specifies the directory in which to search for layouts or wrappers. By default,
it is set to C<_layouts>.

=item * C<source>

Specifies the directory in which source files reside. Source files are files
which will be compiled to HTML if they have a registered convertor and a YAML
configuration in the beginning. By default, it is set to C<_source>.

=item * C<blog_source>

Specifies the directory in which source files for blog posts reside. By default, 
it is set to C<_blog_source>. Note that blog source file must have the following format:
C<YYYYMMDD_title.$extension>!

=item * C<destination>

This directory will be created if it does not exist. Compiled and output files
are placed in this directory. By default, it is set to C<_site>.

=back

=item C<compile>

Each file in the L</C<source>> directory is checked to see if it has a
registered convertor as well as a YAML configuration at the beginning. All such
files are compiled considering the L</YAML Configuration Keys> and the compiled
output is placed in the L</C<destination>> directory. The rest of the files are
copied over to the L</C<destination>> without compiling.

=back

=head2 YAML Configuration Keys

L</YAML Configuration Keys> should be placed at the beginning of the file and
should be enclosed within a pair of C<--->.

Example of using a layout along with a custom key and compiling a markdown
L</C<source>> file:

L</layout> file - C<main.html>:

    <!DOCTYPE html>
    <html>
        <head>
            <title></title>
        </head>
        <body>
            [% content %]
        </body>
    </html>

L</source> file - C<index.markdown>:

    ---
    layout: main.html
    drink : water
    ---
    Drink **plenty** of [% drink %].

L</destination> (output/compiled) file - C<index.html>:

    <!DOCTYPE html>
    <html>
        <head>
            <title></title>
        </head>
        <body>
            <p>Drink <strong>plenty</strong> of water.</p>

        </body>
    </html>

=over 4

=item * C<layout>

Uses the corresponding layout or wrapper to wrap the compiled content. Note that
C<content> is a special variable used in C<L<Template Toolkit|Template>> along
with wrappers. This variable contains the processed wrapped content. In essence,
the output/compiled file will have the C<content> variable replaced with the
compiled L</C<source>> file.

=item * C<I<custom keys>>

These keys will be available for use in the same page as well as in the layout.
In the above example, C<drink> is a custom key.

=back

=head2 Pre-defined template variables

Some variables are automatically made available to the
templates. Apart from C<content> described elsewhere, these are all
prefixed C<sv_> to differentiate them from user variables.

=over

=item sv_rel_base

If the generated web-site is being used without a web-server (i.e. just
on the local file-system), or perhaps if it may be moved around in the
web-server hierarchy, then absolute URIs to shared resouces like CSS
or JS will not work.

Relative paths can be used in these situations.

C<sv-rel-base> provides a relative path from the source file being
processed to the top of the generated web-site. This means that layout
files can refer to shared files like CSS using the following in a
layout file:

    <link rel="stylesheet" type="text/css" href="[% sv_rel_base %]css/bootstrap.css" />

For top level source files, this expands to C<./>. For any
sub-directories, it expands to C<../>, C<../../> etc. Sub-directory
expansions always include the trailing slash.

=item includes, layouts, source, destination, blog_destination

The path to the includes-, layouts-, source-, destination- and blog-destination
directories (see new-constructor for further information). I don't know whether this can be helpful.

=item page

With <% page.$key %> you can get all informations of the current page. $key can be one of
'filename', 'url', 'pagedirectory', 'pagefile' (= the same as filename, in later versions
this can be deleted)

=item pages

With <% pages %> you can access an array with all static pages and the informations of the
pages (see above unde page)

=item post

With <% post.$key %> you can get all informations of the current blog post. $key can be one of
'filename', 'date', 'date_raw', 'teaser', 'tags' (if set in the YAML part) and every name/value 
pair in the YAML part.

=item posts

With C< <% posts %> > you can access an array with all posts and ther informations of the posts (see 
above under post). Useful for a news list. 

=item posts.$tag (TO DO)

With C< <% posts_$tag %> > you can access an array with all posts of the specified tag $tag.

=item posts_YYYYMM (TO DO)

With C< <% posts_YYYYMM %> > you can access an array with all posts of the specified month.

=item blogindexfiles

With <% blogindexfiles %> you can access an array with all blogindexfiles and the informations of the
pages (see above unde page)

=item paginator

In a blogindex file where in the YAML configuration the number of posts per page is set with C<pagination: $n>
to a true value you can access the following variables: 

	paginaror.per_pages (= Number of posts per page; set with the pagination option in the YAML part)
	paginator.total_posts (= total number of posts)
	paginator.total_pages (= total number of pages)
	paginator.posts ( posts avaible of the current page)
	next_page_link (relative link adress to the next page)
  	first_page_link (relative link adress to the first page) 
  	previous_page_link ((relative link adress to the previous page)
    	page (to do; the number of the current page)
    	next_page (to do;the number of the next page)
    	previous_page (to do; the number of the previous page)
    	
If in the YAML part categories is set, the paginator.posts contain only posts of the specified category (not yet
implemented)!

=item staticfiles

With C<staticfiles> you can access an array with all static files.

=item directories

With C<directories> you can access an array with all directories.

=back

=head1 Walkthrough

Consider the source file C<index.markdown> which contains:

    ---
    layout : main.html
    title  : Just an example title
    heading: StaticVolt Example
    ---

    StaticVolt Example
    ==================

    This is an **example** page.

Let C<main.html> which is a wrapper or layout contain:

    <!DOCTYPE html>
    <html>
        <head>
            <title>[% title %]</title>
        </head>
        <body>
            [% content %]
        </body>
    </html>

During compilation, all variables defined as L</YAML Configuration Keys> at the
beginning of the file will be processed and be replaced by their values in the
output file C<index.html>. A registered convertor
(C<L<StaticVolt::Convertor::Markdown>>) is used to convert the markdown text to
HTML.

Compiled output file C<index.html> contains:

    <!DOCTYPE html>
    <html>
        <head>
            <title>Just an example title</title>
        </head>
        <body>
            <h1>StaticVolt Example</h1>
            <p>This is an <strong>example</strong> page.</p>

        </body>
    </html>

=head1 Default Convertors

=over 4

=item * C<L<StaticVolt::Convertor::Markdown>>

=item * C<L<StaticVolt::Convertor::Textile>>

=back

=head1 How to build a convertor?

The convertor should inherit from L<C<StaticVolt::Convertor>>. Define a
subroutine named C<L<StaticVolt::Convertor/convert>> that takes a single argument. This argument should
be converted to HTML and returned.

Register filename extensions by calling the C<register> method inherited from
L<C<StaticVolt::Convertor>>. C<register> accepts a list of filename extensions.

A convertor template that implements conversion from a hypothetical format
I<FooBar>:

    package StaticVolt::Convertor::FooBar;

    use strict;
    use warnings;

    use base qw( StaticVolt::Convertor );

    use Foo::Bar qw( foobar );

    sub convert {
        my $content = shift;
        return foobar $content;
    }

    # Handle files with the extensions:
    #   .foobar, .fb, .fbar, .foob
    __PACKAGE__->register(qw/ foobar fb fbar foob /);

=head1 Inspiration

L<StaticVolt> is inspired by Tom Preston-Werner's L<Jekyll|http://jekyllrb.com/>.

=head1 Success Stories

Charles Wimmer successfully uses StaticVolt to generate and maintain his
L<website|http://www.wimmer.net/>. He describes it in his
L<post|http://www.wimmer.net/sysadmin/2012/08/11/hosting-a-static-website-in-the-cloud/>.

If you wish to have your website listed here, please send an e-mail to
C<haggai@cpan.org>, and I will be glad to list it here. :-)

=head1 Contributors

L<Gavin Shelley|https://github.com/columbusmonkey>

=head1 Acknowledgements

L<Shlomi Fish|http://www.shlomifish.org/> for suggesting change of licence.

=head1 See Also

L<Template Toolkit|Template>

=head1 AUTHOR

Alan Haggai Alavi <haggai@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by Alan Haggai Alavi.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut
