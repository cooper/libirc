#---------------------------------------------------
# libirc: an insanely flexible perl IRC library.   |
# Copyright (c) 2011, the NoTrollPlzNet developers |
# Utils.pm: various IRC-related tools              |
#---------------------------------------------------
package IRC::Utils;

use warnings;
use strict;

# remove the colon from colon-prefixed strings
sub col {
    my $str = shift;
    $str =~ s/^://;
    return $str
}

# escape quotes and escapes
sub escape {
    my $str = shift;
    $str =~ s/('|"|\\)/\\$1/g;
    return $str
}

package bool;
sub true  () { 1 }
sub false () { 0 }

1
