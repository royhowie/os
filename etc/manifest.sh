#!/bin/bash
# to run: ./manifest input_file output_file

export FNAME=tmp_$RANDOM

# remove comments and blank lines
grep -v '//' $1 | grep -v '/\*' | grep -ve '^$' | sort -f > $FNAME.withoutcomments

# blank the output file
cat /dev/null > $2

# begin manifest
echo -n 'manifest{' >> $2

# Read through the file line by line. 
# On each line, apply
#   sed s/\s*//g;       remove all whitespace
#   sed s/$/,/;         replace newlines with commas
#   print the result
# Pass to tr and remove all newline characters
# Reverse the output
# Remove the last two characters (last newline and comma)
# Reverse again and append to the output file
perl -lne 's/\s*//g; s/$/,/g; print' < $FNAME.withoutcomments | tr -d '\n' | rev | cut -c 2- | rev >> $2
# perl -lne 's/\s*//g; s/$/,/; print' < $FNAME.withoutcomments | rev | cut -c 2- | rev >> $2

# end manifest
echo '}' >> $2

# begin export block
echo -n 'export {' >> $2

# Like before, read through the file line by line.
# Except this time, delete everything after the first
# space. This effectively grabs every variable name
# from $FNAME.withoutcomments.
perl -lne 's/\s+.*/,/; print' < $FNAME.withoutcomments | tr -d '\n' | rev | cut -c 3- | rev >> $2

# end constant block
echo -n '}' >> $2

rm $FNAME.withoutcomments
