#!/bin/bash

# Colors
RED="\033[1;31m" # For errors / warnings
GREEN="\033[1;32m" # For info
YELLOW="\033[1;33m" # For input requests
BLUE="\033[1;36m" # For info
NC="\033[0m" # reset color

# Making sure $OUT is populated
if [[ $OUT == '' ]]; then
  echo -e "${RED}Please lunch the target device.${NC}"
  echo -e "${RED}Also make sure a build exists in out folder${NC}"
  exit 1
fi

# Global vars
REPO="Updater-Stuff" # Name of the update repo
REMOTE="https://github.com/DerpLab" # URL to the remote git
BRANCH="master" # Default branch name
DEVICE=$(basename $OUT) # Device name
ZIP_PATH=$(find $OUT -maxdepth 1 -type f -name "Derp*${DEVICE}*.zip" | sed -n -e "1{p;q}")
ZIP=$(basename $ZIP_PATH)
DATE=$(echo $ZIP | sed -n -e "s/^.*${DEVICE}-//p")
DATE="${DATE:0:4}-${DATE:4:2}-${DATE:6:2}"

echo
echo -e "${RED}WARNING! If you have vanilla in a seperate folder - work manually to upload that version!${NC}"
echo

# Cloning / Fetching Updater-Stuff repo if needed be
if [[ -d $REPO ]]; then
  cd $REPO
  git remote update origin
  git checkout origin/$BRANCH
  # also make sure no pending changes
  git restore --staged .
  git restore .
  git clean -f
else
  git clone $REMOTE/$REPO
  cd $REPO
fi

# Making sure device folder exists and is empty
if [[ -d $DEVICE ]]; then
  cd $DEVICE
  rm -f "${DEVICE}.json"
  rm -f Changelog.txt
  rm -f changelog.txt
else
  echo -e "${GREEN}New device: ${BLUE}${DEVICE}${GREEN} - creating folder${NC}"
  mkdir $DEVICE
  cd $DEVICE
fi

# Making sure info.sh is there. If not - generate
if ! [[ -f info.sh ]]; then
  echo
  echo -e "${RED}Did not find info.sh - prompting for info${NC}"
  echo
  echo -en "${YELLOW}Enter device name (not codename) > ${NC}"
  read ans
  echo "DEVICE_NAME=\"${ans}\"" > info.sh
  echo -en "${YELLOW}Enter telegram tag (without @) > ${NC}"
  read ans
  echo "TGNAME=\"${ans}\"" >> info.sh
  echo -en "${YELLOW}Enter name of maintainer > ${NC}"
  read ans
  echo "MAINTAINER=\"${ans}\"" >> info.sh
  echo -en "${YELLOW}Enter link to discussion (xda / tg group) > ${NC}"
  read ans
  echo "DISCUSSION=\"${ans}\"" >> info.sh
  # Comitting and pushing info.sh
  git add info.sh
  git commit -m "${DEVICE}: Add info.sh"
  git --no-pager diff HEAD^
  echo
  echo -e "${RED}Make sure changes are correct!${NC}"
  echo -en "${YELLOW}Push changes (already committed)? y/[n] > ${NC}"
  read ans
  if [[ $ans == 'y' ]]; then
    git push origin HEAD:$BRANCH
  else
    echo -e "${RED}Warning!! Update will not be posted to channel with no info.sh!${NC}"
    echo -e "${RED}It will have to be reuploaded${NC}"
  fi
fi

# Upload build
useSF='n'
echo -en "${YELLOW}Upload ${BLUE}${ZIP}${YELLOW}? y/[n] > ${NC}"
read ans
if [[ $ans == 'y' ]]; then
  echo -e "${GREEN}Uploading build${NC}"
  scp -o StrictHostKeyChecking=no $ZIP_PATH "${DEVICE}@upload.derpfest.org":"/home/${DEVICE}/"
  echo -e "${GREEN}Uploading md5sum${NC}"
  scp -o StrictHostKeyChecking=no "${ZIP_PATH}.md5sum" "${DEVICE}@upload.derpfest.org":"/home/${DEVICE}/"
  echo -en "${YELLOW}Mirror ${BLUE}${ZIP}${YELLOW} to SourceForge? y/[n] > ${NC}"
  read ans
  if [[ $ans == 'y' ]]; then
    echo -en "${YELLOW}Enter SourceForge username: ${NC}"
    read userName
    echo -e "${GREEN}Uploading build${NC}"
    scp $ZIP_PATH "${userName}@frs.sourceforge.net":"/home/frs/p/derpfest/${DEVICE}"
    echo "Uploading md5sum"
    scp "${ZIP_PATH}.md5sum" "${userName}@frs.sourceforge.net":"/home/frs/p/derpfest/${DEVICE}"
    echo -en "${YELLOW}Use SourceForge for OpenDelta (OTA)? y/[n] > ${NC}"
    read useSF
  fi
fi

# Copying generated Changelog and .json file and committing changes
cp "${OUT}/${DEVICE}.json" ./
cp "${OUT}/Changelog.txt" ./
isCustomLink=0
if [[ $useSF == 'y' ]]; then
  isCustomLink=1
  customLink="https://sourceforge.net/projects/derpfest/files/${DEVICE}/${ZIP}/download"
  customMD5="https://sourceforge.net/projects/derpfest/files/${DEVICE}/${ZIP}.md5sum/download"
else
  echo -en "${YELLOW}Use a custom url for OpenDelta (OTA)? y/[n] > ${NC}"
  read ans
  if [[ $ans == 'y' ]]; then
    isCustomLink=1
    echo -en "${YELLOW}Enter a direct zip download link > ${NC}"
    read customLink
    echo -en "${YELLOW}Enter a direct md5sum download link > ${NC}"
    read customMD5
  fi
fi
if [[ $isCustomLink == 1 ]]; then
  sed -ie 5's/$/,&/' "${DEVICE}.json"
  sed -i "6i\ \ \ \ \ \"url\": \"${customLink}\"," "${DEVICE}.json"
  sed -i "7i\ \ \ \ \ \"md5url\": \"${customMD5}\"" "${DEVICE}.json"
fi
cd ..
git add .
git commit -m "${DEVICE}: ${DATE} update"

# Pushing changes
echo
git --no-pager diff HEAD^
echo
echo -e "${RED}Make sure changes are correct!${NC}"
echo -e "${RED}Only push after build and md5 checksum are properly uploaded${NC}"
echo -en "${YELLOW}Push changes (already committed)? y/[n] > ${NC}"
read ans
if [[ $ans == 'y' ]]; then
  git push origin HEAD:$BRANCH
fi
