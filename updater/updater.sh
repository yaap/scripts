#!/bin/bash

# Making sure $OUT is populated
if [[ $OUT == '' ]]; then
  echo "Please lunch the target device."
  echo "Also make sure a build exists in out folder"
  exit 1
fi

REPO="Updater-Stuff" # Name of the update repo
REMOTE="https://github.com/DerpLab" # URL to the remote git
BRANCH="master" # Default branch name
DEVICE=$(basename $OUT) # Device name
ZIP_PATH=$(find $OUT -maxdepth 1 -type f -name "Derp*.zip" | sed -n -e "1{p;q}")
ZIP=$(basename $ZIP_PATH)
DATE=$(echo $ZIP | sed -n -e "s/^.*${DEVICE}-//p")
DATE="${DATE:0:4}-${DATE:4:2}-${DATE:6:2}"
# Upload build to SourceForge
echo -n "Upload ${ZIP} to SourceForge ? y/[n] > "
read ans
if [[ $ans == 'y' ]]; then
  echo -n "Enter SourceForge username: "
  read userName
  echo "Uploading build"
  scp $ZIP_PATH "${userName}@frs.sourceforge.net":"/home/frs/p/derpfest/${DEVICE}"
  echo "Uploading md5sum"
  scp "${ZIP_PATH}.md5sum" "${userName}@frs.sourceforge.net":"/home/frs/p/derpfest/${DEVICE}"
fi

# Cloning / Fetching Updater-Stuff repo if needed be
if [[ -d $REPO ]]; then
  cd $REPO
  git fetch --all
  git checkout origin/$BRANCH
else
  git clone $REMOTE/$REPO
  cd $REPO
fi

# Making sure device folder exists and is empty
if [[ -d $DEVICE ]]; then
  cd $DEVICE
  rm ./*
else
  echo "New device: ${DEVICE} - creating folder"
  mkdir $DEVICE
  cd $DEVICE
fi

# Copying generated Changelog and .json file and committing changes
cp "${OUT}/${DEVICE}.json" ./
cp "${OUT}/Changelog.txt" ./
cd ..
git add .
git commit -m "${DEVICE}: ${DATE} update"

# Pushing changes
echo
git --no-pager diff HEAD^
echo
echo "Make sure changes are correct!"
echo "Only push after build and md5 checksum are properly uploaded"
echo -n "Push changes (already committed)? y/[n] > "
read ans
if [[ $ans == 'y' ]]; then
  git push origin HEAD:$BRANCH
fi
