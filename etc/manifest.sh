export FNAME=temp_file_$RANDOM

# create a temporary output file
touch $FNAME

# remove comments
grep -v '//' $1 > $FNAME.withoutcomments

# remove all white-space characters and store in $FNAME
sed -E "s/[\s]+//" $FNAME.withoutcomments  > $FNAME

# reformat the constants
sed -E "s/([a-zA-Z0-9_]+)[         ]+([a-zA-Z0-9_]+)/\1 = \2, /" $FNAME > $FNAME.tmp

# remove newline characters (requires file shuffle)
mv $FNAME.tmp $FNAME
tr -d '\n' < $FNAME > $FNAME.tmp
mv $FNAME.tmp $FNAME

# start the manifest
echo -n "manifest { " > $FNAME.tmp

# append the constants
cat $FNAME >> $FNAME.tmp

# delete the temp file
mv $FNAME.tmp $FNAME

# remove the trailing characters
cat $FNAME | rev | cut -c 3- | rev > $FNAME.tmp
mv $FNAME.tmp $FNAME

# end the manifest
echo -n " }" >> $FNAME

tr -d '\n' < $FNAME > $FNAME.tmp
mv $FNAME.tmp $2
rm $FNAME

# grab the constants without values and print them in $FNAME.tmp
perl -lne 's/\s+.*/, /; print' < $FNAME.withoutcomments | tr -d '\n' | rev | cut -c 3- | rev > $FNAME.tmp

# 0. add a newline
# 1. begin export struct
# 2. add constants from perl command
# 3. close export struct
echo "" >> $2
echo -n "export { " >> $2
echo -n $(cat $FNAME.tmp) >> $2
echo -ne " }\c" >> $2

# remove the temporary files
rm $FNAME.tmp
rm $FNAME.withoutcomments
