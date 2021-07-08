#!/bin/bash
#
# Copyright (C) 2021 Yet Another AOSP Project
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
    echo "Usage: ${0} (--delete-staging) (--push-staging) (--diff) (--check) <oldaosptag> <newaosptag>"
}

gco_original() {
    lineNO=$(grep -nw -m 1 $PROJECTPATH $SAVEDBRANCHES | grep -Eo '^[^:]+')
    if [[ $? == 0 ]]; then
        line=$(sed "${lineNO}q;d" $SAVEDBRANCHES)
        line=$(echo $line | sed "s,^.*-> ,,")
        echo -e "Returning to ${BLUE}${line}${NC} on ${BLUE}${PROJECTPATH}${NC}"
        git checkout $line > /dev/null 2>&1
    else
        echo -en "${YELLOW}Default branch for ${BLUE}${PROJECTPATH}${YELLOW} not found. "
        echo -e "Checking out to ${BLUE}${DEFAULTREMOTE0}/${DEFAULTBRANCH}${NC}"
        git checkout $DEFAULTREMOTE/$DEFAULTBRANCH > /dev/null 2>&1
    fi
    git branch -D $STAGINGBRANCH
    echo -e "Removed ${BLUE}${STAGINGBRANCH}${NC}"
}

git_push() {
    echo -en "Push changes to default branch ${BLUE}${DEFAULTBRANCH}${NC} "
    echo -en "in ${BLUE}${PROJECTPATH}${NC}? y/[n] > "
    read ans
    if [[ $ans == 'y' ]]; then
        echo "#### Pushing and returning to default remote and branch ####"
        git push $DEFAULTREMOTE $STAGINGBRANCH:$DEFAULTBRANCH
        git checkout $DEFAULTREMOTE/$DEFAULTBRANCH > /dev/null 2>&1
        git branch -d $STAGINGBRANCH
        echo -en "${GREEN}"
        echo -e "pushed\t\t${PROJECTPATH}" | tee -a $MERGEDREPOS
        echo -en "${NC}"
    fi
}

# Verifies there are no uncommitted changes on the current path
verify_committed() {
    if [[ -n "$(git status --porcelain)" ]]; then
        echo -e "${RED}Path ${BLUE}${PROJECTPATH}${RED} has uncommitted changes.${NC}" >&2
        git --no-pager diff
        git --no-pager diff --staged
        echo -en "${YELLOW}Clear uncommitted changes (see above) y/[n] > ${NC}"
        read ans
        if [[ $ans == 'y' ]]; then
            git restore .
            git clean -f .
        else
            exit 1
        fi
    fi
}

# verifies that a project was pushed. helper for sanity_check()
# returns 1 on error, 0 otherwise
# NOTE! Macro use only! $MERGEDREPOS & $PROJECTPATH must be set
push_check() {
    cat $MERGEDREPOS | grep -w $PROJECTPATH | grep -w pushed
    if [[ $? != 0 ]]; then
        isErr=1
        echo -e "${RED}Project ${BLUE}${PROJECTPATH}${RED} was not pushed${NC}" >&2
    fi
}

# verifies that the merge was done successfully
sanity_check() {
    isErr=0
    isWarn=0
    for PROJECTPATH in ${PROJECTPATHS}; do
        cat $MERGEDREPOS | grep -w $PROJECTPATH
        if [[ $? != 0 ]]; then
            isErr=1
            echo -e "${RED}Project ${BLUE}${PROJECTPATH}${RED} was skipped${NC}" >&2
            continue
        fi
        cat $MERGEDREPOS | grep -w $PROJECTPATH | grep -w invalid
        if [[ $? == 0 ]]; then
            echo -en "${YELLOW}Project ${BLUE}${PROJECTPATH}${YELLOW} was marked as "
            echo -e "invalid but is not blacklisted${NC}"
            continue
        fi
        cat $MERGEDREPOS | grep -w $PROJECTPATH | grep -w fail
        if [[ $? == 0 ]]; then
            echo -en "${YELLOW}Project ${BLUE}${PROJECTPATH}${YELLOW} failed the merge "
            echo -e "and was skipped by user${NC}"
            continue
        fi
        cat $MERGEDREPOS | grep -w $PROJECTPATH | grep -w nochange
        [[ $? == 0 ]] && continue # no change in this repo
        cat $MERGEDREPOS | grep -w $PROJECTPATH | grep -w clean
        if [[ $? == 0 ]]; then
            # merged clean. did we push?
            push_check
            continue
        fi
        cat $MERGEDREPOS | grep -w $PROJECTPATH | grep -w solved
        if [[ $? == 0 ]]; then
            # solved conflicts. did we push?
            push_check
            continue
        fi
        cat $MERGEDREPOS | grep -w $PROJECTPATH | grep -w conflict
        if [[ $? == 0 ]]; then
            # conflicts kept. did we solve it?
            cd $PROJECTPATH
            git merge HEAD &> /dev/null
            if [[ $? != 0 ]]; then # a merge is in progress
                isErr=1
                echo -e "${RED}Conflicts in ${BLUE}${PROJECTPATH}${RED} were not solved${NC}" >&2
            else # solved. did we push?
                push_check
            fi
            cd $TOP
            continue
        fi
        # if we arrived here and project is marked as pushed we have no data to decide
        cat $MERGEDREPOS | grep -w $PROJECTPATH | grep -w pushed
        if [[ $? == 0 ]]; then
            echo -e "${YELLOW}Project ${BLUE}${PROJECTPATH}${YELLOW} was pushed with no merge${NC}"
        fi
    done
    if [[ $isErr == 1 ]]; then
        echo -e "${RED}Errors found - view above${NC}" >&2
    else
        echo -en "${GREEN}Sanity check passed"
        if [[ $isWarn == 1 ]]; then
            echo -en " with warnings - view above"
        fi
        echo -e "${NC}"
    fi
    exit $isErr
}

# Handle flags
flagCount=0
isRemoveStaging=0
isPushStaging=0
isDiff=0
isCheck=0
while [[ $# > 2 ]]; do
    case "$1" in
        "--delete-staging") # delete the staging branch
            echo -en "Are you sure? y/[n] > "
            read ans
            if [[ $ans == 'y' ]]; then
                isRemoveStaging=1
            else
                echo -e "${RED}Aborting${NC}"
                exit 0
            fi
            ((flagCount++))
            shift
            ;;
        "--push-staging") # push all remaining staging branches to default remote/branch
            isPushStaging=1
            if [[ $isCheck == 1 ]]; then
                isCheck=0
            else
                ((flagCount++))
            fi
            shift
            ;;
        "--diff") # show the diff between old and new tags and exit
            isDiff=1
            ((flagCount++))
            shift
            ;;
        "--check") # check for sanity
            if [[ $isPushStaging != 1 ]]; then
                isCheck=1
                ((flagCount++))
            fi
            shift
            ;;
        -*|--*) # unsupported flags
            echo -e "${RED}Unsupported flag ${BLUE}$1${NC}" >&2
            usage
            exit 1
            ;;
    esac
done

# Verify argument count
if [ "$#" -ne 2 ]; then
    usage
    exit 1
fi
# Verify there is no more than 1 flag
if [[ $flagCount > 1 ]]; then
    echo -e "${RED}Only use one flag at a time${NC}" >&2
    exit 1
fi
OLDTAG="${1}"
NEWTAG="${2}"

# Check to make sure this is being run from the top level repo dir
if [ ! -e "build/envsetup.sh" ]; then
    echo -e "${RED}Must be run from the top level repo dir${NC}" >&2
    exit 1
fi

# Source build environment (needed for aospremote)
. build/envsetup.sh

# global vars / settings
DEFAULTBRANCH="eleven" # default branch name
DEFAULTREMOTE="yaap" # default remote name
WAIT_ON_CONFLICT=true # should the script halt to allow fixing conflicts

TOP="${ANDROID_BUILD_TOP}"
MERGEDREPOS="${TOP}/merged_repos.txt"
SAVEDBRANCHES="${TOP}/saved_branches.list"
MANIFEST="${TOP}/.repo/manifests/snippets/yaap.xml"
STAGINGBRANCH="staging/${DEFAULTBRANCH}-${NEWTAG}"

# Build a list of forked repos
PROJECTPATHS=$(grep "remote=\"$DEFAULTREMOTE\"" "${MANIFEST}" | sed -n 's/.*path="\([^"]\+\)".*/\1/p')

# Remove blacklisted (non-aosp / not to merge) repos
for PROJECTPATH in ${PROJECTPATHS}; do
    if grep -q -x $PROJECTPATH $TOP/scripts/aosp-merger/merge_blacklist.txt; then
        PROJECTPATHS=("${PROJECTPATHS[@]/$PROJECTPATH}")
    fi
done

echo -en "Old tag = ${BLUE}${OLDTAG}${NC} Branch = ${BLUE}${DEFAULTBRANCH}${NC} "
echo -e "Staging branch = ${BLUE}${STAGINGBRANCH}${NC} Remote = ${BLUE}${DEFAULTREMOTE}${NC}"
echo

if [[ $isPushStaging == 1 ]]; then
    echo "#### Pushing all remaining staging branches ####"
    for PROJECTPATH in ${PROJECTPATHS}; do
        cd "${TOP}/${PROJECTPATH}"

        LOCALBRANCH=$(git rev-parse --abbrev-ref HEAD)
        if [[ $LOCALBRANCH == $STAGINGBRANCH ]]; then # if checked out to the staging branch
            verify_committed
            git_push
        fi
    done
    echo -en "${YELLOW}Is the merge done (check for sanity)? [n]/y > ${NC}"
    read ans
    if [[ $ans == 'y' ]]; then
        sanity_check
    fi
    exit 0
fi

if [[ $isRemoveStaging == 1 ]]; then
    echo -e "#### Removing all staging branches for tag ${BLUE}${NEWTAG}${NC} ####"
    for PROJECTPATH in ${PROJECTPATHS}; do
        cd "${TOP}/${PROJECTPATH}"
        git show-ref --verify --quiet refs/heads/$STAGINGBRANCH
        # if staging branch exists on the repo
        if [[ $? == 0 ]]; then
            gco_original
        fi
    done
    echo -e "${GREEN}Removed ${BLUE}${STAGINGBRANCH}${GREEN} from all forked repos${NC}"
    exit 0
fi

if [[ $isDiff == 1 ]]; then
    echo -en "${YELLOW}Save the diff to a file? [y]/n > ${NC}"
    read ans
    if [[ $ans != 'n' ]]; then
        if [[ -f "${TOP}/${NEWTAG}.diff" ]]; then
            rm "${TOP}/${NEWTAG}.diff"
        fi
        touch "${TOP}/${NEWTAG}.diff"
        echo "Diff from ${OLDTAG} to ${NEWTAG}:" >> "${TOP}/${NEWTAG}.diff"
        echo >> "${TOP}/${NEWTAG}.diff"
    fi
    echo -e "#### Showing diff from ${BLUE}${OLDTAG}${NC} to ${BLUE}${NEWTAG}${NC} ####"
    for PROJECTPATH in ${PROJECTPATHS}; do
        cd "${TOP}/${PROJECTPATH}"
        aospremote
        echo -e "Diff for ${BLUE}${PROJECTPATH}${NC}"
        git fetch -q --tags aosp "${OLDTAG}"
        git fetch -q --tags aosp "${NEWTAG}"
        if [[ $ans != 'n' ]]; then
            echo "Diff for ${PROJECTPATH}:" >> "${TOP}/${NEWTAG}.diff"
            git --no-pager diff $OLDTAG $NEWTAG | tee -a "${TOP}/${NEWTAG}.diff"
            echo >> "${TOP}/${NEWTAG}.diff"
        else
            git --no-pager diff $OLDTAG $NEWTAG
        fi
    done
    if [[ $ans != 'n' ]]; then
        echo -e "Diff file saved at ${BLUE}${TOP}/${NEWTAG}.diff${NC}"
    fi
    exit 0
fi

[[ $isCheck == 1 ]] && sanity_check

# Handle and create an empty list file of saved branches
isReuse=0
if [[ -f $SAVEDBRANCHES ]]; then
    i=0
    echo -e "${YELLOW}Saved branches file exist.${NC}"
    echo "1. Remove (default)"
    echo "2. Rename"
    echo "3. Reuse (resume)" # for aborted merge in progress
    echo -n "Select > "
    read ans
    case $ans in
        "2")
            while [[ -f "${i}${SAVEDBRANCHES}" ]]; do
                ((i++))
            done
            mv $SAVEDBRANCHES "${i}${SAVEDBRANCHES}"
            touch "${SAVEDBRANCHES}"
            echo -e "Renamed to ${BLUE}${i}${SAVEDBRANCHES}${NC}"
            ;;
        "3")
            isReuse=1
            ;;
        *)
            rm -f $SAVEDBRANCHES
            ;;
    esac
else
    touch "${SAVEDBRANCHES}"
fi

# Remove any existing list of merged repos file
[[ $isReuse == 0 ]] && rm -f "${MERGEDREPOS}"

# Make sure manifest and forked repos are in a consistent state
echo "#### Verifying there are no uncommitted changes on forked AOSP projects and saving local branches ####"
for PROJECTPATH in ${PROJECTPATHS} .repo/manifests; do
    cd "${TOP}/${PROJECTPATH}"
    verify_committed

    if [[ $isReuse == 0 ]]; then
        # save the current branch
        LOCALBRANCH=$(git rev-parse --abbrev-ref HEAD)
        if [[ $LOCALBRANCH != "HEAD" ]]; then
            echo "${PROJECTPATH} -> ${LOCALBRANCH}" >> $SAVEDBRANCHES
        else
            echo "${PROJECTPATH} -> ${DEFAULTREMOTE}/${DEFAULTBRANCH}" >> $SAVEDBRANCHES
        fi
        # Making sure we are checked-out to the head of the default remote
        git checkout $DEFAULTREMOTE/$DEFAULTBRANCH
    fi
done
echo -e "${GREEN}#### Verification complete - no uncommitted changes found ####${NC}"
cd $TOP

# Merging build/make & manifest
if [[ $isReuse == 0 ]]; then
    echo "#### Merging build/make & manifest ####"
    cd .repo/manifests
    git checkout -b "${STAGINGBRANCH}"
    git branch --set-upstream-to=origin/$DEFAULTBRANCH
    git fetch https://android.googlesource.com/platform/manifest $NEWTAG
    git merge FETCH_HEAD
    cd ../../build/make
    git checkout -b "${STAGINGBRANCH}"
    git branch --set-upstream-to=$DEFAULTREMOTE/$DEFAULTBRANCH
    git fetch https://android.googlesource.com/platform/build $NEWTAG
    git merge FETCH_HEAD
    echo -e "${GREEN}#### build/make & manifest merged. ${RED}Please push manually at the end${GREEN} ####${NC}"
    echo -e "Press any key to continue"
    read -n 1 -r -s
fi

# Sync
if [[ $isReuse == 0 ]]; then
    repo sync -j$(nproc)
    if [[ $? != 0 ]]; then
        echo -e "${RED}Sync failed. Fix the errors and press any key to continue${NC}" >&2
        read -n 1 -r -s
    fi
fi

# Iterate over each forked project
for PROJECTPATH in ${PROJECTPATHS}; do
    if [[ $isReuse == 0 ]]; then
        # skip if we already did
        if [[ ! -z $(cat $MERGEDREPOS | grep -w $PROJECTPATH) ]]; then
            echo -e "Project ${BLUE}${PROJECTPATH}${NC} was found. Skipping"
            continue
        fi
        echo -e "${GREEN}Resuming at ${BLUE}${PROJECTPATH}${NC}"
    fi
    cd "${TOP}/${PROJECTPATH}"
    git checkout $DEFAULTREMOTE/$DEFAULTBRANCH
    git checkout -b "${STAGINGBRANCH}"
    git branch --set-upstream-to=$DEFAULTREMOTE/$DEFAULTBRANCH
    aospremote
    git fetch -q --tags aosp "${NEWTAG}"

    # Making sure aosp remote is valid
    if [[ $? != 0 ]]; then
        echo -en "${RED}"
        echo -e "invalid\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
        echo -e "${NC}"
        echo -en "${YELLOW}Add to blacklist? [y]/n > ${NC}"
        read ans
        if [[ $ans != 'n' ]]; then
            echo $PROJECTPATH >> $TOP/scripts/aosp-merger/merge_blacklist.txt
            echo -e "Added ${BLUE}${PROJECTPATH}${NC} to blacklist"
        fi
        gco_original
        continue
    fi

    # Was there any change upstream? Return to default branch and skip if not.
    if [[ -z "$(git diff ${OLDTAG} ${NEWTAG})" ]]; then
        echo -en "${GREEN}"
        echo -e "nochange\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
        echo -e "${NC}"
        gco_original
        continue
    fi

    echo -e "#### Merging ${BLUE}${NEWTAG}${NC} into ${BLUE}${PROJECTPATH}${NC} ####"
    git merge --no-edit --log "${NEWTAG}"
    if [[ $? != 0 && ! $(git status --porcelain) ]]; then
        echo -e "${RED}Merge failed${NC}"
        echo "1. Skip (default)"
        echo "2. Mark as solved"
        echo "3. Add to blacklist"
        echo -n "Select > "
        read ans
        case $ans in
            "2")
                echo -en "${GREEN}"
                echo -e "solved\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
                echo -e "${NC}"
                git_push
                continue
                ;;
            "3")
                echo -en "${RED}"
                echo -e "invalid\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
                echo -e "${NC}"
                echo $PROJECTPATH >> $TOP/scripts/aosp-merger/merge_blacklist.txt
                echo -e "Added ${BLUE}${PROJECTPATH}${NC} to blacklist"
                gco_original
                continue
                ;;
            *)
                echo -en "${RED}"
                echo -e "fail\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
                echo -en "${NC}"
                gco_original
                continue
                ;;
        esac
    fi

    if [[ -n "$(git status --porcelain)" ]]; then
        echo -e "${RED}Conflict(s) in ${BLUE}${PROJECTPATH}${NC}"
        if [[ $WAIT_ON_CONFLICT == true ]]; then
            echo -e "${YELLOW}Press 'c' when all merge conflicts are resolved - ${RED}do not commit ${NC}"
            echo -e "${YELLOW}Press 'l' to keep conflicts for later solving and continue the merge${NC}"
            while read -s -r -n 1 lKey; do
                if [[ $lKey == 'c' ]]; then
                    git add .
                    git merge --continue
                    echo -en "${GREEN}"
                    echo -e "solved\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
                    echo -e "${NC}"
                    git_push
                    break;
                elif [[ $lKey == 'l' ]]; then
                    break;
                fi
            done
        fi
        if [[ $WAIT_ON_CONFLICT == false ]] || [[ $lKey == 'l' ]]; then
            echo -en "${RED}"
            echo -e "conflict\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
            echo -en "${NC}"
        fi
    else
        echo -e "${GREEN}Merged ${BLUE}${PROJECTPATH}${GREEN} with no conflicts${NC}"
        echo -e "clean\t\t${PROJECTPATH}" >> "${MERGEDREPOS}"
        git_push
    fi
done

echo -en "${YELLOW}Is the merge done (check for sanity)? [n]/y > ${NC}"
read ans
if [[ $ans == 'y' ]]; then
    sanity_check
fi

exit 0
