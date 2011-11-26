package StaticVolt::Convertor::Textile;

use strict;
use warnings;

use base qw( StaticVolt::Convertor );

use Text::Textile qw( textile );

sub convert {
    my $content = shift;
    return textile $content;
}

__PACKAGE__->register(qw/ textile /);

1;
