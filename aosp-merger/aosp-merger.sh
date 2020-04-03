#!/bin/bash
#
# Copyright (C) 2020 DerpFest Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Colors
RED="\033[1;31m" # For errors / warnings
GREEN="\033[1;32m" # For info
YELLOW="\033[1;33m" # For input requests
BLUE="\033[1;36m" # For info
NC="\033[0m" # reset color

usage() {
    echo "Usage ${0} <oldaosptag> <newaosptag>"
}

# Verify argument count
if [ "$#" -ne 2 ]; then
    usage
    exit 1
fi

OLDTAG="${1}"
NEWTAG="${2}"

# Check to make sure this is being run from the top level repo dir
if [ ! -e "build/envsetup.sh" ]; then
    echo -e "${RED}Must be run from the top level repo dir${NC}"
    exit 1
fi

# Source build environment (needed for aospremote)
. build/envsetup.sh

# global vars / settings
DEFAULTBRANCH="ten" # default branch name
DEFAULTREMOTE="derp" # default remote name
WAIT_ON_CONFLICT=true # should the script halt to allow fixing conflicts

TOP="${ANDROID_BUILD_TOP}"
MERGEDREPOS="${TOP}/merged_repos.txt"
SAVEDBRANCHES="${TOP}/saved_branches.list"
MANIFEST="${TOP}/.repo/manifests/snippets/aosip.xml"
STAGINGBRANCH="staging/${DEFAULTBRANCH}-${NEWTAG}"

# Build a list of forked repos
PROJECTPATHS=$(grep "remote=\"$DEFAULTREMOTE\"" "${MANIFEST}" | sed -n 's/.*path="\([^"]\+\)".*/\1/p')

# Remove blacklisted (non-aosp / not to merge) repos
for PROJECTPATH in ${PROJECTPATHS}; do
    if grep -q $PROJECTPATH $TOP/scripts/aosp-merger/merge_blacklist.txt; then
        PROJECTPATHS=("${PROJECTPATHS[@]/$PROJECTPATH}")
    fi
done

echo -e "Old tag = ${BLUE}${OLDTAG}${NC} Branch = ${BLUE}${DEFAULTBRANCH}${NC} Staging branch = ${BLUE}${STAGINGBRANCH}${NC} Remote = ${BLUE}${DEFAULTREMOTE}${NC}"

# Make sure manifest and forked repos are in a consistent state
echo "#### Verifying there are no uncommitted changes on forked AOSP projects ####"
for PROJECTPATH in ${PROJECTPATHS} .repo/manifests; do
    cd "${TOP}/${PROJECTPATH}"
    if [[ -n "$(git status --porcelain)" ]]; then
        echo -e "${RED}Path ${BLUE}${PROJECTPATH}${RED} has uncommitted changes. Please fix.${NC}"
        exit 1
    fi
    # Making sure we are checked-out to the head of the default remote
    git checkout $DEFAULTREMOTE/$DEFAULTBRANCH
done
echo -e "${GREEN}#### Verification complete - no uncommitted changes found ####${NC}"

# Remove any existing list of merged repos file
rm -f "${MERGEDREPOS}"

# Sync and detach from current branches
repo sync -d

# Iterate over each forked project
for PROJECTPATH in ${PROJECTPATHS}; do
    cd "${TOP}/${PROJECTPATH}"
    repo start "${STAGINGBRANCH}" .
    aospremote
    git fetch -q --tags aosp "${NEWTAG}"

    # Check if we've actually changed anything before attempting to merge
    # If we haven't, just "git reset --hard" to the tag
    if [[ -z "$(git diff HEAD ${OLDTAG})" ]]; then
        git reset --hard "${NEWTAG}"
        echo -en "${GREEN}"
        echo -e "reset\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
        echo -en "${NC}"
        continue
    fi

    # Was there any change upstream? Skip if not.
    if [[ -z "$(git diff ${OLDTAG} ${NEWTAG})" ]]; then
        echo -en "${GREEN}"
        echo -e "nochange\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
        echo -e "${NC}"
        continue
    fi

    echo -e "#### Merging ${BLUE}${NEWTAG}${NC} into ${BLUE}${PROJECTPATH}${NC} ####"
    git merge --no-edit --log "${NEWTAG}"

    if [[ -n "$(git status --porcelain)" ]]; then
        echo -e "${RED}Conflict(s) in ${BLUE}${PROJECTPATH}${NC}"
        if [[ $WAIT_ON_CONFLICT == true ]]; then
            echo -e "${YELLOW}Press 'c' when all merge conflicts are resolved - ${RED}do not commit ${NC}"
            while read -s -r -n 1 lKey; do
                if [[ $lKey == 'c' ]]; then
                    break;
                fi
            done
            git add .
            git merge --continue
            echo -en "Push changes to default branch ${BLUE}${DEFAULTBRANCH}${NC}? y/[n] > "
            read ans
            if [[ $ans == 'y' ]]; then
                echo "#### Pushing and returning to default remote and branch ####"
                git push $DEFAULTREMOTE $STAGINGBRANCH:$DEFAULTBRANCH
                git checkout $DEFAULTREMOTE/$DEFAULTBRANCH
                git branch --delete $STAGINGBRANCH
                echo
                echo "pushed-${PROJECTPATH}" >> $MERGEDREPOS
            else
                echo "${PROJECTPATH}" >> $MERGEDREPOS
            fi
        else
            echo -en "${RED}"
            echo -e "conflict\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
            echo -en "${NC}"
        fi
    else
        echo -e "${GREEN}Merged ${BLUE}${PROJECTPATH}${GREEN} with no conflicts${NC}"
        echo -n "Push changes to default branch ${BLUE}${DEFAULTBRANCH}${NC}? y/[n] > "
        read ans
        if [[ $ans == 'y' ]]; then
            echo "#### Pushing and returning to default remote and branch ####"
            git push $DEFAULTREMOTE $STAGINGBRANCH:$DEFAULTBRANCH
            git checkout $DEFAULTREMOTE/$DEFAULTBRANCH
            git branch --delete $STAGINGBRANCH
            echo
            echo "pushed-\t\t${PROJECTPATH}" >> $MERGEDREPOS
        else
            echo "${PROJECTPATH}" >> $MERGEDREPOS
        fi
    fi

done
