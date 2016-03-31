export FNAME=temp_file_$RANDOM

touch $FNAME

sed -E "s/[\s]+//" $1 > $FNAME
sed -E "s/([a-zA-Z0-9_]+)[         ]+([a-zA-Z0-9_]+)/\1 = \2, /" $FNAME > $FNAME.tmp
mv $FNAME.tmp $FNAME
tr -d '\n' < $FNAME > $FNAME.tmp
mv $FNAME.tmp $FNAME

echo -n "manifest { " > $FNAME.tmp
cat $FNAME >> $FNAME.tmp
mv $FNAME.tmp $FNAME

cat $FNAME | rev | cut -c 3- | rev > $FNAME.tmp
# cut -c 2- < $FNAME > $FNAME.tmp
mv $FNAME.tmp $FNAME

echo -n " }" >> $FNAME

tr -d '\n' < $FNAME > $FNAME.tmp
mv $FNAME.tmp $2
rm $FNAME

perl -lne 's/\s+.*/, /; print' < testfile.txt | tr -d '\n' | rev | cut -c 3- | rev > $FNAME.tmp

echo "" >> $2
echo -n "export { " >> $2
echo -n $(cat $FNAME.tmp) >> $2
echo -ne " }\c" >> $2

rm $FNAME.tmp
